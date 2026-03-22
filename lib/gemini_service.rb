require 'gemini-ai'
require 'json'

module Koine
  class GeminiService
    def initialize(api_key)
      @client = Gemini.new(
        credentials: {
          api_key: api_key
        },
        options: { model: 'gemini-1.5-flash' }
      )
    end

    def extract_expense_from_text(text)
      prompt = <<~PROMPT
        Você é um assistente financeiro. Extraia informações de gastos deste texto: "#{text}".
        Retorne APENAS um JSON no formato:
        {"item": "nome do item", "valor": 0.0, "categoria": "escolha uma categoria lógica", "data": "YYYY-MM-DD"}
        Se houver múltiplos gastos, retorne um array de JSONs: [{"item":...}, {...}]
        Use a data de hoje #{Time.now.strftime('%Y-%m-%d')} se não for informada.
        Se não for um gasto, retorne null.
      PROMPT

      response = @client.generate_content({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { response_mime_type: "application/json" }
      })

      parse_response(response)
    end

    def extract_expense_from_audio(audio_path)
      # Nota: A gem gemini-ai suporta envio de mídia. 
      # Convertemos o áudio para base64 conforme exigido pela API do Gemini.
      audio_data = Base64.strict_encode64(File.read(audio_path))
      
      prompt = "Extraia os gastos deste áudio. Retorne APENAS JSON: {\"item\": \"nome\", \"valor\": 0.0, \"categoria\": \"...\", \"data\": \"YYYY-MM-DD\"}"

      response = @client.generate_content({
        contents: [{
          parts: [
            { text: prompt },
            { inline_data: { mime_type: "audio/ogg", data: audio_data } }
          ]
        }],
        generationConfig: { response_mime_type: "application/json" }
      })

      parse_response(response)
    end

    private

    def parse_response(response)
      text = response.dig('candidates', 0, 'content', 'parts', 0, 'text')
      return nil if text.nil? || text.strip == 'null'
      
      JSON.parse(text)
    rescue JSON::ParserError
      nil
    end
  end
end
