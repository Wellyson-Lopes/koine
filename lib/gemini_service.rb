require 'http'
require 'json'
require 'base64'

module Koine
  class GeminiService
    def initialize(api_key)
      @api_key = api_key
      # Usamos o modelo Gemini 2.5 Flash, confirmado como disponível na sua conta
      @url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=#{@api_key}"
    end

    def extract_expense_from_text(text)
      prompt = <<~PROMPT
        Você é um assistente financeiro. Extraia informações de gastos deste texto: "#{text}".
        Retorne APENAS um JSON no formato:
        {"item": "nome do item", "valor": 0.0, "categoria": "escolha uma categoria lógica", "data": "YYYY-MM-DD"}
        Se houver múltiplos gastos, retorne um array de JSONs.
        Use a data de hoje #{Time.now.strftime('%Y-%m-%d')} se não for informada.
        Se não for um gasto, retorne null.
      PROMPT

      payload = {
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { 
          response_mime_type: "application/json" 
        }
      }

      call_api(payload)
    end

    def extract_expense_from_audio(audio_path)
      audio_data = Base64.strict_encode64(File.read(audio_path))
      
      prompt = "Extraia os gastos deste áudio. Retorne APENAS JSON: {\"item\": \"nome\", \"valor\": 0.0, \"categoria\": \"...\", \"data\": \"YYYY-MM-DD\"}"

      payload = {
        contents: [{
          parts: [
            { text: prompt },
            { inline_data: { mime_type: "audio/ogg", data: audio_data } }
          ]
        }],
        generationConfig: { 
          response_mime_type: "application/json" 
        }
      }

      call_api(payload)
    end

    def extract_expense_from_image(image_path)
      image_data = Base64.strict_encode64(File.read(image_path))
      
      prompt = <<~PROMPT
        Analise esta foto de nota fiscal ou recibo. 
        Extraia as informações de gastos. Retorne APENAS um JSON no formato:
        {"item": "nome do estabelecimento ou item principal", "valor": 0.0, "categoria": "categoria", "data": "YYYY-MM-DD"}
        Se houver múltiplos itens importantes, pode retornar um array.
        Se não conseguir ler um gasto, retorne null.
      PROMPT

      payload = {
        contents: [
          {
            role: 'user',
            parts: [
              { text: prompt },
              { inline_data: { mime_type: "image/jpeg", data: image_data } }
            ]
          }
        ],
        generationConfig: { response_mime_type: "application/json" }
      }

      call_api(payload)
    end

    def call_api(payload)
      response = HTTP.post(@url, json: payload)
      
      if response.status.success?
        result = JSON.parse(response.body.to_s)
        text = result.dig('candidates', 0, 'content', 'parts', 0, 'text')
        return nil if text.nil? || text.strip == 'null'
        
        # Limpa possíveis markdowns e parseia o JSON final
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
