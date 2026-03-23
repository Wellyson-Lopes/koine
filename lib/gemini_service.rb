require 'http'
require 'json'
require 'base64'

module Koine
  class GeminiService
    def initialize(api_key)
      @api_key = api_key
      @url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=#{@api_key}"
      @cooldown_until = Time.now # Memória de bloqueio
    end

    def process_message(text, context = nil)
      return check_cooldown if Time.now < @cooldown_until

      prompt = <<~PROMPT
        Você é o Koine, um assistente financeiro inteligente.
        Hoje é: #{Time.now.strftime('%Y-%m-%d')}
        Contexto de gastos: #{context || "Nenhum dado."}

        Responda à mensagem: "#{text}"
        Retorne APENAS um JSON:
        {
          "intent": "SAVE" (despesa), "INCOME" (recebimento), "QUERY", "ADVICE" ou "OTHER",
          "data": { "item": "...", "valor": 0.0, "categoria": "...", "data": "YYYY-MM-DD" },
          "response": "Sua resposta amigável aqui"
        }
      PROMPT

      payload = { contents: [{ parts: [{ text: prompt }] }] }
      call_api(payload)
    end

    def process_audio(audio_path, context = nil)
      return check_cooldown if Time.now < @cooldown_until
      audio_data = Base64.strict_encode64(File.read(audio_path))

      prompt = <<~PROMPT
        Você é o Koine, um assistente financeiro amigável. Ouça o áudio e responda de forma NATURAL e CONCISA.
        Contexto atual de gastos: #{context || "Vazio"}
        Hoje é: #{Time.now.strftime('%Y-%m-%d')}

        Sua resposta será convertida em áudio, então:
        - NÃO use símbolos como *, _, # ou R$.
        - Escreva valores por extenso quando possível (ex: dez reais).
        - Seja breve e direto, como um áudio de WhatsApp.

        Retorne APENAS um JSON:
        {
          "intent": "SAVE", "INCOME", "QUERY", "ADVICE" ou "OTHER",
          "data": { "item": "...", "valor": 0.0, "categoria": "...", "data": "YYYY-MM-DD" },
          "response": "Sua frase curta e natural para áudio aqui"
        }
      PROMPT

      payload = {
        contents: [{
          parts: [
            { text: prompt },
            { inline_data: { mime_type: "audio/mp3", data: audio_data } }
          ]
        }]
      }
      call_api(payload)
    end

    def extract_expense_from_image(image_path)
      return check_cooldown if Time.now < @cooldown_until
      image_data = Base64.strict_encode64(File.read(image_path))
      # ... resto do código de imagem ...
      prompt = "Analise a nota fiscal. Extraia gasto em JSON: {\"item\": \"...\", \"valor\": 0.0, \"categoria\": \"...\", \"data\": \"YYYY-MM-DD\"}"

      payload = {
        contents: [{
          parts: [
            { text: prompt },
            { inline_data: { mime_type: "image/jpeg", data: image_data } }
          ]
        }]
      }
      call_api(payload)
    end

    private

    def check_cooldown
      remaining = (@cooldown_until - Time.now).ceil
      { "intent" => "OTHER", "response" => "⚠️ Sistema em resfriamento. Por favor, aguarde mais exatos #{remaining} segundos para liberar seu acesso. ⏳" }
    end

    def call_api(payload)
      response = HTTP.post(@url, json: payload)

      if response.status.success?
        result = JSON.parse(response.body.to_s)
        text = result.dig('candidates', 0, 'content', 'parts', 0, 'text')
        return { "intent" => "OTHER", "response" => "..." } if text.nil? || text.strip == 'null'

        json_match = text.match(/\{.*\}/m)
        return { "intent" => "OTHER", "response" => text } if json_match.nil?

        JSON.parse(json_match[0])
      elsif response.status.code == 429
        begin
          error_body = response.body.to_s
          error_data = JSON.parse(error_body)

          # Tenta pegar do campo 'message' via Regex
          message = error_data.dig('error', 'message') || ""
          seconds_match = message.match(/retry in ([\d\.]+)/)

          seconds = 30 # Default
          if seconds_match
            seconds = seconds_match[1].to_f.ceil
          else
            details = error_data.dig('error', 'details') || []
            retry_info = details.find { |d| d['@type']&.include?('RetryInfo') }
            if retry_info
              delay = retry_info['retryDelay']
              seconds = delay.is_a?(Hash) ? delay['seconds'].to_i : delay.to_s.gsub('s', '').to_i
            end
          end

          # GRAVA NA MEMÓRIA LOCAL: bloqueia por X segundos + 2s de segurança
          @cooldown_until = Time.now + seconds + 2

          { "intent" => "OTHER", "response" => "⚠️ Limite atingido! O Google pede para aguardar #{seconds} segundos. Vou bloquear novas tentativas até lá para garantir o reset. ⏳" }
        rescue => e
          @cooldown_until = Time.now + 30
          { "intent" => "OTHER", "response" => "⚠️ Limite atingido! Aguarde 30 segundos e tente novamente." }
        end
      else
        { "intent" => "OTHER", "response" => "Tive um soluço técnico aqui. Pode tentar novamente?" }
      end
    rescue => e
      { "intent" => "OTHER", "response" => "Não consegui processar sua mensagem agora." }
    end
  end
end
