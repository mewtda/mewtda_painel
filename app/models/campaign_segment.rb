class CampaignSegment < ApplicationRecord
  belongs_to :campaign
  belongs_to :segment
end
