require 'http'
require 'json'
require 'base64'

module Koine
  class GeminiService
    def initialize(api_key)
      @api_key = api_key
      @url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=#{@api_key}"
    end

    def process_message(text, context = nil)
      prompt = <<~PROMPT
        Você é o Koine, um assistente financeiro inteligente e amigável.
        Data de hoje: #{Time.now.strftime('%Y-%m-%d')}
        Contexto de gastos atuais: #{context || "Nenhum dado disponível ainda."}

        Identifique a intenção do usuário na mensagem: "#{text}"
        Retorne APENAS um JSON válido no formato do exemplo abaixo:
        {
          "intent": "SAVE",
          "data": { "item": "café", "valor": 5.0, "categoria": "alimentação", "data": "2024-03-20" },
          "response": "Sua resposta amigável aqui"
        }

        VALORES PERMITIDOS PARA 'intent':
        - SAVE: Use para novos gastos.
        - QUERY: Use para perguntas sobre gastos (ex: "Quanto gastei com café?"). Extraia em 'data': {"termo_busca": "termo", "periodo": "período"}
        - ADVICE: Use para conselhos financeiros baseados no contexto.
        - OTHER: Conversas genéricas ou saudações.

        REGRAS:
        - Se for SAVE, preencha 'data' com item, valor, categoria e data.
        - Se for QUERY ou ADVICE, use o campo 'response' para responder amigavelmente.
      PROMPT

      payload = {
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { response_mime_type: "application/json" }
      }

      call_api(payload)
    end

    def process_audio(audio_path, context = nil)
      audio_data = Base64.strict_encode64(File.read(audio_path))
      
      prompt = <<~PROMPT
        Você é o Koine, um assistente financeiro. Ouça o áudio anexo e identifique a intenção.
        Contexto atual de gastos: #{context || "Vazio"}
        Hoje é: #{Time.now.strftime('%Y-%m-%d')}

        Retorne APENAS um JSON válido no formato do exemplo abaixo:
        {
          "intent": "SAVE",
          "data": { "item": "lanche", "valor": 10.0, "categoria": "comida", "data": "2024-03-20" },
          "response": "Sua resposta amigável aqui"
        }

        VALORES PERMITIDOS PARA 'intent': SAVE, QUERY, ADVICE, OTHER.
      PROMPT

      payload = {
        contents: [
          {
            role: 'user',
            parts: [
              { text: prompt },
              { inline_data: { mime_type: "audio/ogg", data: audio_data } }
            ]
          }
        ],
        generationConfig: { response_mime_type: "application/json" }
      }

      call_api(payload)
    end

    def extract_expense_from_image(image_path)
      # Mantemos o de imagem focado em extração por enquanto
      image_data = Base64.strict_encode64(File.read(image_path))
      prompt = "Analise esta foto de nota fiscal. Extraia gasto em JSON: {\"item\": \"...\", \"valor\": 0.0, \"categoria\": \"...\", \"data\": \"YYYY-MM-DD\"}"

      payload = {
        contents: [{
          parts: [
            { text: prompt },
            { inline_data: { mime_type: "image/jpeg", data: image_data } }
          ]
        }],
        generationConfig: { response_mime_type: "application/json" }
      }

      call_api(payload)
    end

    private

    def call_api(payload)
      response = HTTP.post(@url, json: payload)
      if response.status.success?
        result = JSON.parse(response.body.to_s)
        text = result.dig('candidates', 0, 'content', 'parts', 0, 'text')
        return nil if text.nil? || text.strip == 'null'
        JSON.parse(text.gsub(/```json|```/, '').strip)
      else
        puts "Erro na API Gemini: #{response.status} - #{response.body}"
        nil
      end
    rescue => e
      puts "Erro ao processar resposta: #{e.message}"
      nil
    end
  end
end
