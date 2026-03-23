require 'sqlite3'
require 'fileutils'

module Koine
  class Database
    DB_PATH = "data/koine.sqlite3"

    def self.setup
      FileUtils.mkdir_p("data")
      db = SQLite3::Database.new(DB_PATH)
      db.execute <<-SQL
        CREATE TABLE IF NOT EXISTS expenses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          chat_id INTEGER,
          description TEXT,
          amount REAL,
          category TEXT,
          transaction_type TEXT DEFAULT 'saída',
          expense_date DATE,
          raw_text TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
      SQL
      
      # Migração: Atualiza coluna para português se já existir
      begin
        db.execute("ALTER TABLE expenses ADD COLUMN transaction_type TEXT DEFAULT 'saída'")
      rescue SQLite3::SQLException
        # Coluna já existe
      end
      
      db
    end

    def self.conn
      @db ||= setup
    end

    def self.save_transaction(chat_id, data, raw_text, type = 'saída')
      amount = data['valor'].to_s.gsub(',', '.').to_f rescue 0.0
      conn.execute(
        "INSERT INTO expenses (chat_id, description, amount, category, transaction_type, expense_date, raw_text) VALUES (?, ?, ?, ?, ?, ?, ?)",
        [chat_id, data['item'], amount, data['categoria'], type, data['data'] || Time.now.strftime("%Y-%m-%d"), raw_text]
      )
    end

    def self.get_balance(chat_id)
      start_date = Time.now.strftime("%Y-%m-01")
      
      incomes = conn.get_first_value(
        "SELECT SUM(amount) FROM expenses WHERE chat_id = ? AND expense_date >= ? AND transaction_type = 'entrada'",
        [chat_id, start_date]
      ).to_f

      expenses = conn.get_first_value(
        "SELECT SUM(amount) FROM expenses WHERE chat_id = ? AND expense_date >= ? AND transaction_type = 'saída'",
        [chat_id, start_date]
      ).to_f

      { income: incomes, expense: expenses, balance: (incomes - expenses) }
    end

    def self.get_monthly_report(chat_id)
      start_date = Time.now.strftime("%Y-%m-01")
      conn.execute(
        "SELECT category, SUM(amount) FROM expenses WHERE chat_id = ? AND expense_date >= ? AND transaction_type = 'saída' GROUP BY category",
        [chat_id, start_date]
      )
    end

    def self.get_monthly_summary(chat_id)
      start_date = Time.now.strftime("%Y-%m-01")
      rows = conn.execute(
        "SELECT category, SUM(amount) FROM expenses WHERE chat_id = ? AND expense_date >= ? AND transaction_type = 'saída' GROUP BY category",
        [chat_id, start_date]
      )
      rows.map { |row| "#{row[0]}: R$ #{(row[1] || 0.0).round(2)}" }.join(", ")
    end

    def self.search_expenses(chat_id, query)
      conn.execute(
        "SELECT expense_date, description, amount, transaction_type FROM expenses WHERE chat_id = ? AND (description LIKE ? OR category LIKE ?) ORDER BY expense_date DESC LIMIT 10",
        [chat_id, "%#{query}%", "%#{query}%"]
      )
    end

    def self.get_monthly_details_for_excel(chat_id)
      start_date = Time.now.strftime("%Y-%m-01")
      conn.execute(
        "SELECT expense_date, description, category, transaction_type, amount FROM expenses WHERE chat_id = ? AND expense_date >= ? ORDER BY expense_date ASC",
        [chat_id, start_date]
      )
    end

    def self.get_safe_recent_history(chat_id, limit = 10)
      start_date = Time.now.strftime("%Y-%m-01")
      rows = conn.execute(
        "SELECT description, amount, category FROM expenses WHERE chat_id = ? AND expense_date >= ? ORDER BY expense_date DESC LIMIT ?",
        [chat_id, start_date, limit]
      )
      # Trunca descrições para 15 caracteres para privacidade e economia de tokens
      rows.map { |r| "#{r[0].to_s[0..14]}... | R$ #{r[1]} | #{r[2]}" }.join(", ")
    end
  end
end
