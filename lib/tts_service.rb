require 'http'
require 'fileutils'

module Koine
  class TTSService
    # Usaremos uma API gratuita/simples para demonstração
    # ou o Google Cloud TTS se a chave for provida.
    def self.generate_audio(text, chat_id)
      FileUtils.mkdir_p("reports")
      filename = "reports/relatorio_#{chat_id}.mp3"

      # Limpa o texto para o áudio ser mais fluido
      clean_text = text.gsub(/[\*\_\[\]]/, "").gsub(/R\$/, "Reais")
      
      # A API gratuita do Google Translate tem um limite de ~200 caracteres por requisição.
      # Vamos truncar ou pegar apenas o resumo financeiro para garantir o funcionamento.
      audio_text = clean_text.split("\n\n").first(2).join("\n") # Pega cabeçalho e saldo
      encoded_text = URI.encode_www_form_component(audio_text)
      
      url = "https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&q=#{encoded_text}&tl=pt-br"

      # Adicionar User-Agent é CRÍTICO para não ser bloqueado pelo Google
      response = HTTP.headers("User-Agent" => "Mozilla/5.0").follow.get(url)

      if response.status.success?
        File.open(filename, "wb") { |f| f.write(response.body) }
        return filename
      end
      nil
    end
  end
end
