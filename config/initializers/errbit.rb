require "airbrake"

settings = Psych.load_file "#{__dir__}/../config.yaml"

Airbrake.configure do |config|
  config.host = settings["airbrake"]["host"]
  config.project_id = settings["airbrake"]["project_id"]
  config.project_key = settings["airbrake"]["project_key"]

  config.root_directory = File.realdirpath("#{__dir__}/../..")
  config.timeout = 5
  #config.logger.level = Logger::DEBUG
end