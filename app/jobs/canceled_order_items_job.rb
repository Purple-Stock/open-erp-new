# frozen_string_literal: true

# CanceledOrderItemsJob perform against created orders set previously
# with another status.
# For this reason, we should call this job as an updater job.
# We keep the create block as it is since we can not prove bling
# erp first create a e.g. checked status then
# update its own data to the canceled one.
class CanceledOrderItemsJob < BlingOrderItemCreatorBaseJob
  queue_as :default
  STATUS = BlingOrderItem::Status::CANCELED.freeze

  attr_accessor :account_id

  def perform(account_id)
    @account_id = account_id
    begin
      orders = Services::Bling::Order.call(order_command: 'find_orders', tenant: account_id,
                                           situation: STATUS)
      orders = orders['data']

      create_orders(orders)
    rescue StandardError => e
      Rails.logger.error(e.message)
    end
  end

  def create_orders(orders)
    orders_attributes = []

    orders.each do |order|
      orders_attributes << {
        bling_order_id: order['id'],
        situation_id: order['situacao']['id'],
        store_id: order['loja']['id'],
        date: order['data'],
        alteration_date:
      }
    end

    BlingOrderItem.upsert_all(orders_attributes, unique_by: :bling_order_id)
  end
end
