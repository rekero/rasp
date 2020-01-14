# frozen_string_literal: true

require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)
require 'telegram/bot'
require 'mysql2'
TOKEN = ENV.fetch('token')
LOGIN = ENV.fetch('login')
PASSWORD = ENV.fetch('password')

def clean
  sleep 600
  client = Mysql2::Client.new(host: 'localhost', username: LOGIN, database: 'test', password: PASSWORD)
  client.query("UPDATE `messages` SET `active` = '0' WHERE `messages`.`date` < (NOW()-INTERVAL 24 HOUR)")
end

def board
  kb = [
    Telegram::Bot::Types::InlineKeyboardButton.new(text: 'Добавить объявление', callback_data: 'add'),
    Telegram::Bot::Types::InlineKeyboardButton.new(text: 'Получить доску объявлений', callback_data: 'get_list'),
    Telegram::Bot::Types::InlineKeyboardButton.new(text: 'Удалить мои объявления', callback_data: 'remove')
  ]
  Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)
end

def target_keyboard
  kb = [
    Telegram::Bot::Types::InlineKeyboardButton.new(text: 'Ищу команду', callback_data: 'target1'),
    Telegram::Bot::Types::InlineKeyboardButton.new(text: 'Ищу игрока', callback_data: 'target2'),
    Telegram::Bot::Types::InlineKeyboardButton.new(text: 'Ищу тестеров', callback_data: 'target3')
  ]
  Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)
end

def is_admin?(name)
  name == 'rekero' || name == 'FA72t'
end

def help(client, bot, message)
  results = client.query("SELECT * FROM messages WHERE active IS NULL AND author = '#{escaped}'").to_a
  if results.first['date'].nil?
    bot.api.send_message(chat_id: message.from.id, text: 'Укажите дату в формате ДД.ММ.ГГГГ')
  elsif results.first['hashtag'].nil?
    bot.api.send_message(chat_id: message.chat.id, text: 'Что вам нужно?', reply_markup: target_keyboard)
  elsif results.first['description'].nil?
    bot.api.send_message(chat_id: message.from.id, text: 'Введите объявление про команду, турнир, время и прочие рейтинги')
  end unless results.empty?
end

def work(bot)
  begin
    bot.listen do |message|
      client = Mysql2::Client.new(host: 'localhost', username: LOGIN, database: 'test', password: PASSWORD)
      p message
      escaped = client.escape(message.from.username)
      results = client.query("SELECT * FROM messages WHERE description IS NULL AND author = '#{escaped}'").to_a
      case message
      when Telegram::Bot::Types::CallbackQuery
        case message.data
        when 'target1', 'target2', 'target3'
          hashtag = {'target1' => '#лег', 'target2' => '#ком', 'target3' => '#тест'}[message.data]
          client.query("UPDATE `messages` SET `hashtag` = '#{hashtag}' WHERE  `messages`.`id` = #{results.first['id']}")
          bot.api.send_message(chat_id: message.from.id, text: 'Введите объявление про команду, турнир, время и прочие рейтинги')
        when 'remove'
          client.query("UPDATE `messages` SET `active` = '0' WHERE `messages`.`author` = '#{escaped}'")
        when 'add'
          client.query("INSERT INTO messages (`author`) VALUES ('#{escaped}')") if results.count == 0
          help(client, bot, message)
        when 'get_list'
          active_games = client.query("SELECT * FROM messages WHERE active = '1'").to_a
          if active_games.empty?
            bot.api.send_message(chat_id: message.from.id, text: 'Нет активных объявлений')
          else
            dates = client.query("SELECT DISTINCT date FROM messages WHERE active = '1' ORDER BY date").to_a
            text = String.new
            dates.each do |date|
              games = client.query("SELECT * FROM messages WHERE active = '1' AND date = '#{date['date'].strftime("%Y-%m-%d")}'").to_a
              text << date['date'].strftime("*%d.%m.%Y*")
              text << "\n"
              games.each do |game|
                text << game['id'].to_s if is_admin?(escaped)
                text << "  *#{game['hashtag']}* #{game['description']} Контакты: @#{game['author']}"
                text << "\n"
              end
            end
            bot.api.send_message(chat_id: message.from.id, text: text, parse_mode: 'Markdown')
            bot.api.send_message(chat_id: message.from.id, text: 'Вы админ и можете редактировать объявления следующим образом:') if is_admin?(escaped)
            bot.api.send_message(chat_id: message.from.id, text: 'Команда "/edit Nобъявления Поле Значение"') if is_admin?(escaped)
            bot.api.send_message(chat_id: message.from.id, text: 'Поля - active, date, description, hashtag') if is_admin?(escaped)
          end
        end
      when Telegram::Bot::Types::Message
        if is_admin?(escaped)
          if message.text.include?('/edit')
            args = message.text.split(' ')
            hash = Hash[*args[2..-1]]
            query = String.new
            query << "UPDATE `messages` SET"
            hash.keys.each do |key|
              query << "`#{key}` = '#{hash[key]}'"
              query << ',' unless key == hash.keys.last
            end
            query << "WHERE `messages`.`id` = #{args[1]}"
            client.query(query)
          end
        end
        if results.count > 0
          if results.first['date'].nil?
            day, month, year = message.text.split('.').map(&:to_i)
            if !day || !month || !year || !Date.valid_date?(year, month, day) || Date.new(year, month, day) < Date.today
              bot.api.send_message(chat_id: message.from.id, text: 'Дата некорректная')
            else
              client.query("UPDATE `messages` SET `date` = '#{Date.new(year, month, day)}' WHERE `messages`.`id` = #{results.first['id']}")
            end
          elsif results.first['description'].nil? && !results.first['hashtag'].nil?
            client.query("UPDATE `messages` SET `description` = '#{message.text}', `active` = '1' WHERE `messages`.`id` = #{results.first['id']}")
            bot.api.send_message(chat_id: message.from.id, text: 'Объявление принято')
          end
          help(client, bot, message)
        else
          bot.api.send_message(chat_id: message.chat.id, text: 'Выберите действие', reply_markup: board)
        end
      end
    end
  rescue StandardError => e
    p e.message
    retry
  end
end


begin
  Telegram::Bot::Client.run(TOKEN) do |bot|
    p 'start'
    t1 = Thread.new{work(bot)}
    t2 = Thread.new{clean}
    t1.join
    t2.join
  end
end

