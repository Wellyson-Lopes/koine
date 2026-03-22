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
          expense_date DATE,
          raw_text TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
      SQL
      db
    end

    def self.conn
      @db ||= setup
    end

    def self.save_expense(chat_id, data, raw_text)
      amount = data['valor'].to_s.gsub(',', '.').to_f rescue 0.0
      conn.execute(
        "INSERT INTO expenses (chat_id, description, amount, category, expense_date, raw_text) VALUES (?, ?, ?, ?, ?, ?)",
        [chat_id, data['item'], amount, data['categoria'], data['data'] || Time.now.strftime("%Y-%m-%d"), raw_text]
      )
    end

    def self.get_monthly_report(chat_id)
      start_date = Time.now.strftime("%Y-%m-01")
      conn.execute(
        "SELECT category, SUM(amount) FROM expenses WHERE chat_id = ? AND expense_date >= ? GROUP BY category",
        [chat_id, start_date]
      )
    end

    def self.get_monthly_summary(chat_id)
      start_date = Time.now.strftime("%Y-%m-01")
      rows = conn.execute(
        "SELECT category, SUM(amount) FROM expenses WHERE chat_id = ? AND expense_date >= ? GROUP BY category",
        [chat_id, start_date]
      )
      rows.map { |row| "#{row[0]}: R$ #{row[1].round(2)}" }.join(", ")
    end

    def self.search_expenses(chat_id, query)
      # Busca simples por termo na descrição ou categoria
      conn.execute(
        "SELECT expense_date, description, amount FROM expenses WHERE chat_id = ? AND (description LIKE ? OR category LIKE ?) ORDER BY expense_date DESC LIMIT 10",
        [chat_id, "%#{query}%", "%#{query}%"]
      )
    end

    def self.get_last_expenses(chat_id, limit = 50)
      start_date = Time.now.strftime("%Y-%m-01")
      rows = conn.execute(
        "SELECT expense_date, description, amount, category FROM expenses WHERE chat_id = ? AND expense_date >= ? ORDER BY expense_date DESC LIMIT ?",
        [chat_id, start_date, limit]
      )
      rows.map { |r| "#{r[0]} | #{r[1]} | R$ #{r[2]} | #{r[3]}" }.join("\n")
    end
  end
end
