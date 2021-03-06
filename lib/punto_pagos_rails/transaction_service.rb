module PuntoPagosRails
  class TransactionService
    attr_accessor :process_url
    attr_reader :payable

    SUCCESS_CODE = "99"
    ERROR_CODE = "00"

    def initialize(payable)
      @payable = payable
    end

    def create
      transaction = payable.transactions.create!
      response = PuntoPagos::Request.new.create(
        transaction.id.to_s, transaction.amount_to_s, payable.payment_method)

      if !response.success?
        payable.errors.add(:base, I18n.t("punto_pagos_rails.errors.invalid_puntopagos_response"))
        return false
      end

      init_transaction(transaction, response.get_token).tap do |transaction_result|
        self.process_url = response.payment_process_url if transaction_result
      end
    end

    private

    def init_transaction(transaction, token)
      if token.blank?
        payable.errors.add(:base,
          I18n.t("punto_pagos_rails.errors.invalid_returned_puntopagos_token"))
        return false
      end

      if repeated_token?(token)
        payable.errors.add(:base, I18n.t("punto_pagos_rails.errors.repeated_token_given"))
        return false
      end

      transaction.update!(token: token, amount: payable.amount)
    end

    def repeated_token?(token)
      Transaction.where(token: token).any?
    end

    class << self
      def notificate(params, headers)
        notification = PuntoPagos::Notification.new
        token = params[:token]
        error = params[:error]

        if notification.valid?(headers, params)
          complete_transaction(token)
          { respuesta: SUCCESS_CODE, token: token }
        else
          reject_transaction(token, error)
          { respuesta: ERROR_CODE, error: error, token: token }
        end
      end

      def complete(params)
        transaction = processing_transaction(params[:token])
        return false unless transaction
        status = PuntoPagos::Status.new
        status.check(transaction.token, transaction.id.to_s, transaction.amount_to_s)

        if status.valid?
          complete_transaction(transaction.token)
        else
          reject_transaction(transaction.token, status.error)
        end
      end

      private

      def method_missing(method, *args, &block)
        if method.to_s.ends_with?("_by_token")
          payable_class = method.to_s.chomp("_by_token")
          failed = payable_class.slice!("failed_") if method.to_s.starts_with?("failed_")
          return payable_by_token(payable_class.classify.constantize, args.first, !!failed)
        end

        super
      end

      def payable_by_token(payable_class, params, with_error = false)
        payable = payable_class.by_token(params[:token])

        if payable && with_error
          payable.errors.add(:base, I18n.t("punto_pagos_rails.errors.invalid_puntopagos_payment"))
        end

        payable
      end

      def processing_transaction(token)
        transaction = Transaction.find_by_token(token)
        return unless transaction
        return unless transaction.pending?
        transaction
      end

      def complete_transaction(token)
        transaction = processing_transaction(token)
        return if transaction.nil?
        transaction.complete!
      end

      def reject_transaction(token, error)
        transaction = processing_transaction(token)
        return if transaction.nil?
        transaction.reject_with(error)
      end
    end
  end
end
