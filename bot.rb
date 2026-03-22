require 'telegram/bot'
require 'dotenv/load'
require 'http'
require 'json'
require 'csv'
require 'time'

# Carrega as variáveis de ambiente do arquivo .env
TELEGRAM_TOKEN = ENV['TELEGRAM_BOT_TOKEN']
GEMINI_API_KEY = ENV['GEMINI_API_KEY']
GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent?key=#{GEMINI_API_KEY}"

def analyze_with_gemini(text)
  prompt = <<~PROMPT
    Você é um assistente financeiro que extrai gastos a partir de mensagens informais, áudios ou notas fiscais.
    Da mensagem a seguir, extraia as seguintes informações no formato JSON estrito:
    - descricao: o que foi gasto (ex: "Almoço", "Gasolina")
    - valor: o valor numérico gasto (ex: 25.50)
    - data: a data no formato YYYY-MM-DD (se não for mencionada na mensagem, use a data de hoje: #{Time.now.strftime('%Y-%m-%d')})
    
    Se houver múltiplos itens de gasto, extraia todos eles como um array de objetos JSON.
    Se não houver gasto na mensagem, retorne um JSON vazio [].

    Mensagem: "#{text}"
  PROMPT

  payload = {
    contents: [{ parts: [{ text: prompt }] }],
    generationConfig: { response_mime_type: "application/json" }
  }

  response = HTTP.post(GEMINI_URL, json: payload)
  return nil unless response.status.success?
  
  begin
    result = JSON.parse(response.body.to_s)
    json_text = result.dig('candidates', 0, 'content', 'parts', 0, 'text')
    return JSON.parse(json_text)
  rescue StandardError => e
    puts "Erro ao processar resposta do Gemini: #{e.message}"
    return nil
  end
end

def save_expense_to_csv(expense, filename = "gastos_#{Time.now.strftime('%Y_%m')}.csv")
  file_exists = File.exist?(filename)
  
  CSV.open(filename, "a", col_sep: ";") do |csv|
    csv << ["Data", "Descrição", "Valor"] unless file_exists
    csv << [expense['data'], expense['descricao'], expense['valor']]
  end
end

puts "Bot Koine iniciado. Aguardando mensagens..."

Telegram::Bot::Client.run(TELEGRAM_TOKEN) do |bot|
  bot.listen do |message|
    case message
    when Telegram::Bot::Types::Message
      # Por enquanto lidamos com texto simples para demonstrar
      if message.text == '/start'
        bot.api.send_message(chat_id: message.chat.id, text: "Olá! Sou o Koine, seu assistente financeiro. Envie um texto detalhando seus gastos e eu os registrarei!")
      elsif message.text
        bot.api.send_message(chat_id: message.chat.id, text: "Analisando seu gasto...")
        
        expenses = analyze_with_gemini(message.text)
        
        if expenses && !expenses.empty?
          expenses = [expenses] if expenses.is_a?(Hash) # Se retornar um objeto, transformar em array

          total_registrado = 0
          resposta = "Gasto(s) registrado(s):\n"
          
          expenses.each do |exp|
            save_expense_to_csv(exp)
            resposta += "- #{exp['descricao']} (#{exp['data']}): R$ #{exp['valor']}\n"
            total_registrado += exp['valor'].to_f
          end
          
          resposta += "\nTotal nesta mensagem: R$ #{total_registrado.round(2)}"
          bot.api.send_message(chat_id: message.chat.id, text: resposta)
        else
          bot.api.send_message(chat_id: message.chat.id, text: "Não consegui identificar um gasto na sua mensagem.")
        end
      elsif message.photo || message.voice
        bot.api.send_message(chat_id: message.chat.id, text: "No momento só processo texto, mas a análise de áudio e notas fiscais já está no nosso roadmap de implementação usando a API do Gemini!")
      end
    end
  end
end
