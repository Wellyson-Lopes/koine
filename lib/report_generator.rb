require 'axlsx'
require 'fileutils'

module Koine
  class ReportGenerator
    def self.generate_text(chat_id)
      summary = Database.get_monthly_report(chat_id)
      balance = Database.get_balance(chat_id)
      
      return "Nenhum gasto ou entrada registrado este mês." if summary.empty? && balance[:income] == 0

      report = "*Relatório Mensal - #{Time.now.strftime('%B/%Y')}*\n\n"
      
      report += "📥 *Entradas:* R$ #{sprintf('%.2f', balance[:income])}\n"
      report += "📤 *Saídas:* R$ #{sprintf('%.2f', balance[:expense])}\n"
      report += "💰 *Saldo Líquido: R$ #{sprintf('%.2f', balance[:balance])}*\n\n"

      report += "*Detalhamento por Categoria (Saídas):*\n"
      summary.each do |cat, amount|
        report += "#{cat}: R$ #{sprintf('%.2f', amount)}\n"
      end
      
      report
    end

    def self.generate_excel(chat_id)
      details = Database.get_monthly_details_for_excel(chat_id)
      FileUtils.mkdir_p("reports")
      filename = "reports/gastos_#{chat_id}_#{Time.now.strftime('%Y_%m')}.xlsx"

      Axlsx::Package.new do |p|
        p.workbook.add_worksheet(name: "Movimentações") do |sheet|
          sheet.add_row ["Data", "Descrição", "Categoria", "Tipo", "Valor"]
          details.each do |row|
            sheet.add_row row
          end
        end
        p.serialize(filename)
      end
      filename
    end
  end
end
