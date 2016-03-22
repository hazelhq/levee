module Levee
  class Validator
    attr_accessor :errors, :params, :builder_options, :object

    def initialize(params, object=nil)
      self.errors  = []
      self.object  = object

      if att = params[:attributes]
        self.params = att
      else
        self.params = params
      end
    end

    def validate_params(builder_options = {})
      @builder_options = builder_options
      validations.each { |val| send(val) }
      self
    end

    def add_invalid_request_error(message)
      error = {status: 400, code: 'invalid_request_error', message: message}
      errors << error
    end

    def add_invalid_request_error!(message)
      add_invalid_request_error(message)
      raise message
    end

    def self.validations(*args)
      @validations = args
    end

    def self._validations
      @validations
    end

    def validations
      self.class._validations
    end
  end
end
