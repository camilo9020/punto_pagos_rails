require "punto_pagos_rails/engine"
require "punto_pagos_rails/resource_extension"
require "punto_pagos_rails/transaction_service"

module PuntoPagosRails
  extend self

  attr_accessor :payable_resources

  def setup
    yield self
    require "puntopagos"
  end
end
