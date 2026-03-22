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
      conn.execute(
        "INSERT INTO expenses (chat_id, description, amount, category, expense_date, raw_text) VALUES (?, ?, ?, ?, ?, ?)",
        [chat_id, data['item'], data['valor'], data['categoria'], data['data'] || Time.now.strftime("%Y-%m-%d"), raw_text]
      )
    end

    def self.get_monthly_report(chat_id)
      start_date = Time.now.strftime("%Y-%m-01")
      conn.execute(
        "SELECT category, SUM(amount) FROM expenses WHERE chat_id = ? AND expense_date >= ? GROUP BY category",
        [chat_id, start_date]
      )
    end

    def self.get_monthly_details(chat_id)
      start_date = Time.now.strftime("%Y-%m-01")
      conn.execute(
        "SELECT expense_date, description, category, amount FROM expenses WHERE chat_id = ? AND expense_date >= ? ORDER BY expense_date ASC",
        [chat_id, start_date]
      )
    end
  end
end
