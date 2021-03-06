require 'aasm'

module PuntoPagosRails
  class Transaction < ActiveRecord::Base
    include AASM

    belongs_to :payable, polymorphic: true

    after_save :persist_state_in_payable

    delegate :amount, to: :payable

    aasm column: :state do
      state :pending, initial: true
      state :completed
      state :rejected

      event :complete do
        transitions from: :pending, to: :completed
      end

      event :reject do
        transitions from: :pending, to: :rejected
      end
    end

    def reject_with(error)
      self.error = error
      reject!
    end

    def amount_to_s
      "%0.2f" % amount.to_i
    end

    def persist_state_in_payable
      return unless payable
      payable.update_column(:payment_state, state)
    end
  end
end
