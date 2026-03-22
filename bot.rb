require 'telegram/bot'
require 'dotenv/load'
require 'fileutils'
require 'base64'
require 'http'
require_relative 'lib/database'
require_relative 'lib/gemini_service'
require_relative 'lib/report_generator'
require_relative 'lib/tts_service'

# Carrega ambiente
TELEGRAM_TOKEN = ENV['TELEGRAM_BOT_TOKEN']
GEMINI_API_KEY = ENV['GEMINI_API_KEY']

unless TELEGRAM_TOKEN && GEMINI_API_KEY
  puts "ERRO: Por favor, configure TELEGRAM_BOT_TOKEN e GEMINI_API_KEY no arquivo .env"
  exit
end

# Inicializa serviços
Koine::Database.setup
gemini = Koine::GeminiService.new(GEMINI_API_KEY)

puts "🚀 Koine Analista iniciado..."

Telegram::Bot::Client.run(TELEGRAM_TOKEN) do |bot|
  bot.listen do |message|
    chat_id = message.chat.id rescue nil
    next unless chat_id

    begin
      summary = Koine::Database.get_monthly_summary(chat_id)
      
      # Contexto inteligente: envia histórico detalhado apenas se o usuário pedir análise
      needs_analysis = message.text.to_s.downcase.match?(/redundante|conselho|analis|repete|dica|padrão/)
      
      if needs_analysis
        history = Koine::Database.get_safe_recent_history(chat_id)
        context = "Resumo por categoria: #{summary}\nÚltimos gastos (sanitizados): #{history}"
      else
        context = "Resumo por categoria: #{summary}"
      end

      case message
      when Telegram::Bot::Types::Message
        if message.text == '/start'
          bot.api.send_message(chat_id: chat_id, text: "Olá! Eu sou o Koine, seu analista financeiro. Pode me contar seus gastos, perguntar quanto gastou com algo ou pedir conselhos sobre economia!")

        elsif message.text == '/relatorio'
          bot.api.send_message(chat_id: chat_id, text: "Gerando seu relatório mensal completo... 📊")
          
          # 1. Relatório em Texto
          report_text = Koine::ReportGenerator.generate_text(chat_id)
          bot.api.send_message(chat_id: chat_id, text: report_text, parse_mode: 'Markdown')

          # 2. Planilha Excel
          begin
            excel_path = Koine::ReportGenerator.generate_excel(chat_id)
            if File.exist?(excel_path)
              bot.api.send_document(
                chat_id: chat_id, 
                document: Faraday::UploadIO.new(excel_path, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
                caption: "📈 Planilha detalhada de gastos"
              )
            end
          rescue => e
            puts "Erro ao gerar/enviar Excel: #{e.message}"
            bot.api.send_message(chat_id: chat_id, text: "❌ Não consegui gerar a planilha Excel.")
          end

          # 3. Relatório em Áudio (TTS)
          begin
            audio_report = Koine::TTSService.generate_audio(report_text, chat_id)
            if audio_report && File.exist?(audio_report)
              bot.api.send_voice(
                chat_id: chat_id, 
                voice: Faraday::UploadIO.new(audio_report, 'audio/ogg'),
                caption: "🎙️ Relatório de voz"
              )
            end
          rescue => e
            puts "Erro ao gerar/enviar Áudio: #{e.message}"
            bot.api.send_message(chat_id: chat_id, text: "❌ Não consegui gerar o relatório em voz.")
          end

        elsif message.text
          result = gemini.process_message(message.text, context)
          
          if result.is_a?(Hash)
            case result['intent']
            when 'SAVE'
              exp = result['data']
              Koine::Database.save_expense(chat_id, exp, message.text)
              bot.api.send_message(chat_id: chat_id, text: "✅ Registrado: #{exp['item']} (R$ #{exp['valor']})")
            
            when 'QUERY'
              search_term = result.dig('data', 'termo_busca')
              rows = Koine::Database.search_expenses(chat_id, search_term)
              if rows.empty?
                bot.api.send_message(chat_id: chat_id, text: "Não encontrei gastos relacionados a '#{search_term}'.")
              else
                resp = "Encontrei esses gastos com '#{search_term}':\n"
                rows.each { |r| resp += "- #{r[0]}: #{r[1]} (R$ #{r[2]})\n" }
                bot.api.send_message(chat_id: chat_id, text: resp)
              end

            when 'ADVICE', 'OTHER'
              msg = result['response'] || "Como posso te ajudar?"
              bot.api.send_message(chat_id: chat_id, text: msg) unless msg.strip.empty?
            end
          else
            bot.api.send_message(chat_id: chat_id, text: "🤔 Tive um problema ao entender sua mensagem. Pode repetir ou tentar de outra forma?")
          end

        elsif message.voice || message.audio
          bot.api.send_message(chat_id: chat_id, text: "Analisando seu áudio... 🎧")
          file_id = (message.voice || message.audio).file_id
          file_info = bot.api.get_file(file_id: file_id)
          local_path = "data/temp_audio_#{chat_id}.ogg"
          
          begin
            response = HTTP.follow.get("https://api.telegram.org/file/bot#{TELEGRAM_TOKEN}/#{file_info.file_path}")
            File.open(local_path, "wb") { |f| f.write(response.body) }
            
            result = gemini.process_audio(local_path, context)
            
            if result.is_a?(Hash)
              if result['intent'] == 'SAVE'
                exp = result['data']
                Koine::Database.save_expense(chat_id, exp, "[Áudio]")
                bot.api.send_message(chat_id: chat_id, text: "✅ Áudio processado! Registrei: #{exp['item']} (R$ #{exp['valor']})")
              else
                msg = result['response'] || "Não consegui processar esse áudio."
                bot.api.send_message(chat_id: chat_id, text: msg) unless msg.strip.empty?
              end
            else
              bot.api.send_message(chat_id: chat_id, text: "⚠️ Tive um problema ao ouvir seu áudio. Pode tentar gravar novamente?")
            end
          ensure
            File.delete(local_path) if File.exist?(local_path)
          end

        elsif message.photo
          # O fluxo de foto continua focado em extração de nota por enquanto
          photo = message.photo.last
          file_info = bot.api.get_file(file_id: photo.file_id)
          local_path = "data/temp_photo_#{chat_id}.jpg"
          
          begin
            response = HTTP.follow.get("https://api.telegram.org/file/bot#{TELEGRAM_TOKEN}/#{file_info.file_path}")
            
            if response.status.success?
              File.open(local_path, "wb") { |f| f.write(response.body) }
              result = gemini.extract_expense_from_image(local_path)
              
              if result && (!result.is_a?(Array) || !result.empty?)
                expenses = result.is_a?(Array) ? result : [result]
                expenses.each { |exp| Koine::Database.save_expense(chat_id, exp, "[Foto]") }
                bot.api.send_message(chat_id: chat_id, text: "✅ Nota lida! Registrei: #{expenses.map{|e| e['item']}.join(', ')} (R$ #{expenses.sum{|e| e['valor'].to_f}})")
              else
                bot.api.send_message(chat_id: chat_id, text: "⚠️ Não consegui ler essa nota da foto. Você pode tentar outra foto com melhor iluminação/enquadramento ou digitar o gasto manualmente.")
              end
            else
              bot.api.send_message(chat_id: chat_id, text: "❌ Tive um problema técnico ao baixar sua foto do Telegram.")
            end
          ensure
            File.delete(local_path) if File.exist?(local_path)
          end
        end
      end
    rescue => e
      puts "ERRO: #{e.message}\n#{e.backtrace.first}"
      bot.api.send_message(chat_id: chat_id, text: "⚠️ Tive um problema ao processar isso.") rescue nil
    end
  end
end
