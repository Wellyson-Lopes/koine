require 'http'
require 'fileutils'

module Koine
  class TTSService
    def self.generate_audio(text, chat_id)
      FileUtils.mkdir_p("reports")
      temp_audio = "reports/temp_#{chat_id}.mp3"
      final_ogg = "reports/voz_#{chat_id}.ogg"

      # Limpa o texto
      clean_text = text.gsub(/[\*\_\#]/, "").gsub(/R\$/, "reais").strip

      # Tenta usar ElevenLabs se a chave estiver presente
      api_key = ENV['ELEVENLABS_API_KEY']
      if api_key && !api_key.empty?
        begin
          # Usando o George (ID do seu check_eleven.rb) - Voz quente e cativante
          voice_id = "JBFqnCBsd6RMkjVDRZzb"
          url = "https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}"

          response = HTTP.headers(
            "xi-api-key" => api_key,
            "Content-Type" => "application/json"
          ).post(url, json: {
            text: clean_text,
            model_id: "eleven_multilingual_v2",
            voice_settings: { stability: 0.5, similarity_boost: 0.75 }
          })
          if response.status.success?
            File.open(temp_audio, "wb") { |f| f.write(response.body) }
            system("ffmpeg -y -i #{temp_audio} -c:a libopus -b:a 32k #{final_ogg} > /dev/null 2>&1")
            File.delete(temp_audio) if File.exist?(temp_audio)
            return final_ogg
          end
        rescue
          # Se der erro no ElevenLabs, cai para o fallback do Google abaixo
        end
      end

      # FALLBACK: Google Translate TTS (Gratuito e Infinito)
      begin
        encoded_text = URI.encode_www_form_component(clean_text[0..199])
        url = "https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&q=#{encoded_text}&tl=pt-br"
        response = HTTP.headers("User-Agent" => "Mozilla/5.0").follow.get(url)

        if response.status.success?
          File.open(temp_audio, "wb") { |f| f.write(response.body) }
          system("ffmpeg -y -i #{temp_audio} -c:a libopus -b:a 32k #{final_ogg} > /dev/null 2>&1")
          File.delete(temp_audio) if File.exist?(temp_audio)
          return final_ogg
        end
      rescue
        nil
      end
    end

  end
end
