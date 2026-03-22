require 'http'
require 'json'
require 'dotenv/load'

api_key = ENV['GEMINI_API_KEY']
url = "https://generativelanguage.googleapis.com/v1beta/models?key=#{api_key}"

puts "🔍 Listando modelos disponíveis para sua chave..."

response = HTTP.get(url)

if response.status.success?
  models = JSON.parse(response.body.to_s)
  puts "\nModelos encontrados:"
  models['models'].each do |model|
    if model['supportedGenerationMethods'].include?('generateContent')
      puts "- #{model['name'].gsub('models/', '')} (#{model['displayName']})"
    end
  end
else
  puts "❌ Erro ao listar modelos: #{response.status}"
  puts response.body
end
