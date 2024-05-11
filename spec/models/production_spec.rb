# == Schema Information
#
# Table name: productions
#
#  id           :bigint           not null, primary key
#  consider     :boolean          default(FALSE)
#  cut_date     :datetime
#  deliver_date :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :integer
#  tailor_id    :bigint
#
# Indexes
#
#  index_productions_on_account_id  (account_id)
#  index_productions_on_tailor_id   (tailor_id)
#
# Foreign Keys
#
#  fk_rails_...  (tailor_id => tailors.id)
#
require 'rails_helper'

RSpec.describe Production, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
