require 'rubygems'
require 'sinatra'
require 'haml'
require 'dm-sqlite-adapter'
require 'dm-postgres-adapter'
require 'data_mapper'
require 'rack-flash'
require 'tmail'
require 'postmark'
require 'json'

configure do
  enable :sessions
  use Rack::Flash, :sweep => true
  Postmark.api_key = "api-key-here"
  Postmark.response_parser_class = :Json
end

configure :development do
  DataMapper.setup(:default, "sqlite3://#{File.expand_path(File.dirname(__FILE__))}/db/bcracing_development.db")
end

configure :production do
  DataMapper.setup(:default, ENV['DATABASE_URL'])
end

# DataMapper::Model.raise_on_save_failure = true

class Message
  include DataMapper::Resource
  include DataMapper::Timestamp
  
  # Schema
  property :id,                       Serial
  property :body,                     String, :length => 255
  property :code,                     String, :length => 255
  property :recipients,               Object
  property :created_at,               DateTime
  property :updated_at,               DateTime
  
  # Validations
  validates_length_of :body, :minimum => 1, :max => 70
  validates_with_method :code, :method => :code_must_be
  
  # Hooks/Callbacks
  before :save, :set_recipients
  after :save,  :deliver_reminders
  
  def deliver_reminders
    recipients.each do |recipient|
      deliver_reminder(recipient)
    end
  end
  
  def deliver_reminder(recipient)    
    message = TMail::Mail.new
    # make sure you have a sender signature with that email
    # from and to also accept arrays of emails.
    message.from = "bcracing@scottmotte.com"
    message.to = recipient
    message.subject = ""
    message.content_type = "text/plain"
    message["Message-Id"] = "<#{recipient}>"
    message.body = "BC Racing: #{body}"
    # tag message
    message.tag = "bcracing"
    # set reply to if you need; also, you can pass array of emails.
    message.reply_to = "bcracing@scottmotte.com"
    
    Postmark.send_through_postmark(message)
  end
  
  private
  def set_recipients
    self.recipients = [] # put hard coded array of phone numbers here like 714555265@txt.att.net
  end
  
  def code_must_be
    cleaned_code = code.downcase.strip rescue ""
    if cleaned_code == "landspeeder"
      true
    else
      [false, "Incorrect code"]
    end
  end
end

get "/" do
  redirect "/messages"
end

get "/messages" do
  @message  = Message.new
  @messages = Message.all(:order => :created_at.desc)
  haml :"/messages/index"
end

post "/messages/create" do
  @message = Message.new(params[:message])
  @messages = Message.all(:order => :created_at.desc)
  if @message.save
    flash[:notice] = "Messages sent"
    redirect "/messages"
  else
    flash[:error] = "Message failed to send"
    haml :"/messages/index"
  end
end





# ==================================================
# Helpers
# ==================================================
helpers do
  def error_messages_for(record, options={})
    return "" if record.blank? or record.errors.none?
    record.errors.full_messages
  end
end
