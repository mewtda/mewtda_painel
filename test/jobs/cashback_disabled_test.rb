require 'test_helper'

# Cashback e rastreio saíram junto com a Evolution: os jobs que o Heroku Scheduler ainda chama não enviam nada.
class CashbackDisabledTest < ActiveJob::TestCase
  test 'ProcessCashbackAutomationsJob não processa nenhuma loja' do
    assert ProcessCashbackAutomationsJob::DISABLED
    Client.stub(:where, ->(*) { flunk 'não deveria buscar lojas' }) do
      ProcessCashbackAutomationsJob.perform_now
    end
  end

  test 'CouponExpirationReminderJob termina sem buscar cupons' do
    assert_nothing_raised { CouponExpirationReminderJob.perform_now }
  end
end
