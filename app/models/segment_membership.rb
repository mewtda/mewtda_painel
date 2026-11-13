class SegmentMembership < ApplicationRecord
  belongs_to :segment
  belongs_to :customer
end
