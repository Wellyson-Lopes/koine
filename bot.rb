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

puts "🚀 Koine Bot iniciado..."

Telegram::Bot::Client.run(TELEGRAM_TOKEN) do |bot|
  bot.listen do |message|
    chat_id = message.chat.id rescue nil
    next unless chat_id

    begin
      case message
      when Telegram::Bot::Types::Message
        if message.text == '/start'
          bot.api.send_message(chat_id: chat_id, text: "Olá! Eu sou o Koine. Envie um texto, áudio ou foto de nota fiscal com seus gastos e eu registrarei para você!")

        elsif message.text == '/relatorio'
          bot.api.send_message(chat_id: chat_id, text: "Gerando seu relatório mensal...")
          
          report_text = Koine::ReportGenerator.generate_text(chat_id)
          bot.api.send_message(chat_id: chat_id, text: report_text, parse_mode: 'Markdown')

          excel_path = Koine::ReportGenerator.generate_excel(chat_id)
          if File.exist?(excel_path)
            bot.api.send_document(chat_id: chat_id, document: Faraday::UploadIO.new(excel_path, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'))
          end

          audio_report = Koine::TTSService.generate_audio(report_text, chat_id)
          if audio_report && File.exist?(audio_report)
            bot.api.send_voice(chat_id: chat_id, voice: Faraday::UploadIO.new(audio_report, 'audio/ogg'))
          end

        elsif message.text
          result = gemini.extract_expense_from_text(message.text)
          if result
            expenses = result.is_a?(Array) ? result : [result]
            expenses.each { |exp| Koine::Database.save_expense(chat_id, exp, message.text) }
            bot.api.send_message(chat_id: chat_id, text: "✅ Registrado: #{expenses.map{|e| e['item']}.join(', ')} (R$ #{expenses.sum{|e| e['valor'].to_f}})")
          else
            bot.api.send_message(chat_id: chat_id, text: "🤔 Não consegui identificar um gasto nessa mensagem.")
          end

        elsif message.voice || message.audio
          bot.api.send_message(chat_id: chat_id, text: "Ouvindo seu áudio... 🎧")
          FileUtils.mkdir_p("data")
          
          file_id = (message.voice || message.audio).file_id
          file_info = bot.api.get_file(file_id: file_id)
          file_url = "https://api.telegram.org/file/bot#{TELEGRAM_TOKEN}/#{file_info.file_path}"
          
          local_path = "data/temp_audio_#{chat_id}.ogg"
          
          begin
            response = HTTP.follow.get(file_url)
            if response.status.success?
              File.open(local_path, "wb") { |f| f.write(response.body) }
              result = gemini.extract_expense_from_audio(local_path)
              
              if result
                expenses = result.is_a?(Array) ? result : [result]
                expenses.each { |exp| Koine::Database.save_expense(chat_id, exp, "[Áudio]") }
                bot.api.send_message(chat_id: chat_id, text: "✅ Áudio processado! Registrei: #{expenses.map{|e| e['item']}.join(', ')} (R$ #{expenses.sum{|e| e['valor'].to_f}})")
              else
                bot.api.send_message(chat_id: chat_id, text: "❌ Não entendi o gasto no áudio.")
              end
            end
          ensure
            File.delete(local_path) if File.exist?(local_path)
          end

        elsif message.photo
          bot.api.send_message(chat_id: chat_id, text: "Lendo sua nota fiscal... 📸")
          FileUtils.mkdir_p("data")
          
          photo = message.photo.last
          file_info = bot.api.get_file(file_id: photo.file_id)
          file_url = "https://api.telegram.org/file/bot#{TELEGRAM_TOKEN}/#{file_info.file_path}"
          
          local_path = "data/temp_photo_#{chat_id}.jpg"
          
          begin
            response = HTTP.follow.get(file_url)
            if response.status.success?
              File.open(local_path, "wb") { |f| f.write(response.body) }
              result = gemini.extract_expense_from_image(local_path)
              
              if result
                expenses = result.is_a?(Array) ? result : [result]
                expenses.each { |exp| Koine::Database.save_expense(chat_id, exp, "[Foto]") }
                bot.api.send_message(chat_id: chat_id, text: "✅ Nota lida! Registrei: #{expenses.map{|e| e['item']}.join(', ')} (R$ #{expenses.sum{|e| e['valor'].to_f}})")
              else
                bot.api.send_message(chat_id: chat_id, text: "❌ Não consegui ler os valores dessa nota.")
              end
            end
          ensure
            File.delete(local_path) if File.exist?(local_path)
          end
        end
      end
    rescue => e
      puts "ERRO: #{e.message}"
      puts e.backtrace.join("\n")
      bot.api.send_message(chat_id: chat_id, text: "⚠️ Ocorreu um erro ao processar sua solicitação.") rescue nil
    end
  end
end
