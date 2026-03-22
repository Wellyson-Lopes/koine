# Koine

"Koine" significa "comum" em grego. Este é um projeto para uso no dia a dia, controlando gastos financeiros mensais via Telegram usando a IA do Gemini.

## Funcionalidades
- Envio de áudio ou texto informando os gastos.
- Envio de fotos de notas fiscais.
- IA do Gemini analisa os dados e extrai informações (o que foi gasto, valor, data).
- Geração de planilha mensal com todos os gastos e o valor total.

## Como usar
1. Clone o repositório.
2. Rode `bundle install` para instalar as dependências.
3. Copie o arquivo `.env.example` para `.env` e preencha as chaves:
   - `TELEGRAM_BOT_TOKEN`: Token gerado pelo BotFather no Telegram.
   - `GEMINI_API_KEY`: Chave da API do Google Gemini.
4. Execute o bot com `ruby bot.rb`.
