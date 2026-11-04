module Whatsapp
  class RecoveryJob < ApplicationJob
    queue_as :whatsapp
    def perform = Recovery.call
  end
end
