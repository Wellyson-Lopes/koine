require 'http'
require 'fileutils'
require 'uri'
require 'securerandom'

module Koine
  class TTSService
    def self.generate_audio(text, chat_id)
      FileUtils.mkdir_p("data")
      
      # Gera nomes únicos para evitar condições de corrida (Race Conditions)
      unique_id = SecureRandom.hex(4)
      temp_audio = "data/temp_#{chat_id}_#{unique_id}.mp3"
      final_ogg = "data/voz_#{chat_id}_#{unique_id}.ogg"

      # Limpa o texto e prepara para leitura
      clean_text = text.gsub(/[\*\_\#]/, "").gsub(/R\$/, "reais").strip
      
      # Tenta usar ElevenLabs se a chave estiver presente
      api_key = ENV['ELEVENLABS_API_KEY']
      voice_id = ENV['ELEVENLABS_VOICE_ID'] || "JBFqnCBsd6RMkjVDRZzb" # Default: George

      if api_key && !api_key.empty?
        begin
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
            
            # Converte com ffmpeg de forma segura (sem shell interpolation) e valida sucesso
            success = system("ffmpeg", "-y", "-i", temp_audio, "-c:a", "libopus", "-b:a", "32k", final_ogg, out: File::NULL, err: File::NULL)
            File.delete(temp_audio) if File.exist?(temp_audio)
            
            return final_ogg if success && File.exist?(final_ogg)
          end
        rescue StandardError => e
          # Silencioso, cai para fallback
        end
      end

      # FALLBACK: Google Translate TTS (Gratuito e Infinito)
      begin
        encoded_text = URI.encode_www_form_component(clean_text[0..199])
        url = "https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&q=#{encoded_text}&tl=pt-br"
        response = HTTP.headers("User-Agent" => "Mozilla/5.0").follow.get(url)

        if response.status.success?
          File.open(temp_audio, "wb") { |f| f.write(response.body) }
          
          # Converte com ffmpeg de forma segura (sem shell interpolation) e valida sucesso
          success = system("ffmpeg", "-y", "-i", temp_audio, "-c:a", "libopus", "-b:a", "32k", final_ogg, out: File::NULL, err: File::NULL)
          File.delete(temp_audio) if File.exist?(temp_audio)
          
          return final_ogg if success && File.exist?(final_ogg)
        end
      rescue StandardError => e
        nil
      ensure
        File.delete(temp_audio) if File.exist?(temp_audio)
      end
    end
  end
end
