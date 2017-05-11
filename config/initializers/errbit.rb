require "airbrake"

module Patches
  module Airbrake
    module SyncSender
      def build_https(uri)
        super.tap do |req|
          req.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
      end
    end
  end
end

settings = Psych.load_file "#{__dir__}/../config.yaml"

Airbrake::SyncSender.prepend(::Patches::Airbrake::SyncSender)

Airbrake.configure do |config|
  config.host = settings["airbrake"]["host"]
  config.project_id = settings["airbrake"]["project_id"]
  config.project_key = settings["airbrake"]["project_key"]

  config.root_directory = File.realdirpath("#{__dir__}/../..")
  config.timeout = 5
  #config.logger.level = Logger::DEBUG
end