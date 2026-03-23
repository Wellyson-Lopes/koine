require 'telegram/bot'
require 'dotenv/load'
require 'fileutils'
require 'base64'
require 'http'
require 'faraday'
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
                caption: "📈 Planilha de Fluxo de Caixa (Movimentações)"
              )
            end
          rescue => e
            bot.api.send_message(chat_id: chat_id, text: "❌ Não consegui gerar a planilha Excel.")
          end

          # 3. Relatório em Áudio (TTS)
          begin
            audio_report = Koine::TTSService.generate_audio(report_text, chat_id)
            if audio_report && File.exist?(audio_report)
              bot.api.send_audio(
                chat_id: chat_id, 
                audio: Faraday::UploadIO.new(audio_report, 'audio/mpeg'),
                caption: "🎙️ Relatório de voz (MP3)"
              )
            else
              bot.api.send_message(chat_id: chat_id, text: "🔈 Não foi possível gerar o áudio do relatório.")
            end
          rescue => e
            bot.api.send_message(chat_id: chat_id, text: "❌ Erro ao enviar o relatório em voz.")
          end

        elsif message.text
          # Constroi contexto apenas quando necessário
          summary = Koine::Database.get_monthly_summary(chat_id)
          needs_analysis = message.text.to_s.downcase.match?(/redundante|conselho|analis|repete|dica|padrão/)
          context = "Resumo por categoria: #{summary}"
          context += "\nÚltimos gastos (sanitizados): #{Koine::Database.get_safe_recent_history(chat_id)}" if needs_analysis

          result = gemini.process_message(message.text, context)
          
          if result.is_a?(Hash)
            case result['intent']
            when 'SAVE', 'INCOME'
              type = result['intent'] == 'INCOME' ? 'entrada' : 'saída'
              exp = result['data']
              Koine::Database.save_transaction(chat_id, exp, message.text, type)
              
              # Busca o saldo atualizado
              balance = Koine::Database.get_balance(chat_id)
              status = type == 'entrada' ? "Recebimento registrado! 💰" : "Gasto registrado! 💸"
              
              bot.api.send_message(
                chat_id: chat_id, 
                text: "✅ #{status}\n\nItem: #{exp['item']}\nValor: R$ #{exp['valor']}\n\n📊 *Saldo do Mês:*\nEntradas: R$ #{balance[:income]}\nSaídas: R$ #{balance[:expense]}\n💰 *Líquido: R$ #{balance[:balance].round(2)}*",
                parse_mode: 'Markdown'
              )
            
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
          
          # No áudio enviamos apenas o resumo como contexto base
          context = "Resumo por categoria: #{Koine::Database.get_monthly_summary(chat_id)}"
          
          file_id = (message.voice || message.audio).file_id
          file_info = bot.api.get_file(file_id: file_id)
          local_path = "data/temp_audio_#{chat_id}.ogg"
          
          begin
            response = HTTP.follow.get("https://api.telegram.org/file/bot#{TELEGRAM_TOKEN}/#{file_info.file_path}")
            File.open(local_path, "wb") { |f| f.write(response.body) }
            
            result = gemini.process_audio(local_path, context)
            
            if result.is_a?(Hash)
              if ['SAVE', 'INCOME'].include?(result['intent'])
                type = result['intent'] == 'INCOME' ? 'entrada' : 'saída'
                exp = result['data']
                Koine::Database.save_transaction(chat_id, exp, "[Áudio]", type)
                
                balance = Koine::Database.get_balance(chat_id)
                bot.api.send_message(
                  chat_id: chat_id, 
                  text: "✅ Áudio processado!\nItem: #{exp['item']}\nValor: R$ #{exp['valor']}\n\n💰 *Saldo Líquido: R$ #{balance[:balance].round(2)}*",
                  parse_mode: 'Markdown'
                )
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
                expenses.each { |exp| Koine::Database.save_transaction(chat_id, exp, "[Foto]", "saída") }
                
                balance = Koine::Database.get_balance(chat_id)
                bot.api.send_message(
                  chat_id: chat_id, 
                  text: "✅ Nota lida!\nRegistrado: #{expenses.map{|e| e['item']}.join(', ')}\nTotal: R$ #{expenses.sum{|e| e['valor'].to_f}}\n\n💰 *Saldo Líquido: R$ #{balance[:balance].round(2)}*",
                  parse_mode: 'Markdown'
                )
              else
                bot.api.send_message(chat_id: chat_id, text: "⚠️ Não consegui ler essa nota da foto. Você pode tentar outra foto com melhor iluminação/enquadramento ou digitar o gasto manualmente.")
              end
            else
              bot.api.send_message(chat_id: chat_id, text: "❌ Tive um problema técnico ao baixar sua foto do Telegram. Por favor, tente novamente mais tarde.")
            end
          rescue => e
            bot.api.send_message(chat_id: chat_id, text: "⚠️ Tive um problema técnico ao processar sua foto.")
          ensure
            File.delete(local_path) if File.exist?(local_path)
          end

        end
      end
    rescue => e
      puts "ERRO [#{e.class}]: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      bot.api.send_message(chat_id: chat_id, text: "⚠️ Ocorreu um erro ao processar sua solicitação.") rescue nil
    end
  end
end
