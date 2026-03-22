require 'axlsx'
require 'fileutils'

module Koine
  class ReportGenerator
    def self.generate_text(chat_id)
      summary = Database.get_monthly_report(chat_id)
      return "Nenhum gasto registrado este mês." if summary.empty?

      report = "📊 *Relatório Mensal - #{Time.now.strftime('%B/%Y')}*\n\n"
      total = 0
      summary.each do |cat, amount|
        report += "🔹 #{cat}: R$ #{sprintf('%.2f', amount)}\n"
        total += amount
      end
      report += "\n💰 *Total Geral: R$ #{sprintf('%.2f', total)}*"
      report
    end

    def self.generate_excel(chat_id)
      details = Database.get_monthly_details(chat_id)
      FileUtils.mkdir_p("reports")
      filename = "reports/gastos_#{chat_id}_#{Time.now.strftime('%Y_%m')}.xlsx"

      Axlsx::Package.new do |p|
        p.workbook.add_worksheet(name: "Gastos") do |sheet|
          sheet.add_row ["Data", "Descrição", "Categoria", "Valor"]
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
