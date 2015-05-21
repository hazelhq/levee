module Levee
  class Builder

    attr_accessor :params, 
                  :errors, 
                  :object, 
                  :nested_objects_to_save, 
                  :permitted_attributes, 
                  :requires_save, 
                  :builder_options

    def initialize(params, options={}, &blk)
      set_params_using_adapter(params)
      self.errors                 = []
      self.nested_objects_to_save = []
      self.permitted_attributes   = [:id]
      self.requires_save          = true
      self.builder_options        = options
      @callback_blocks            = [*blk]
    end

    def build
      unless params.is_a? Array
        self.object = object_class.find_by(id: params[:id]) || object_class.new
      end
      assign_parameters_in_transaction
    end

    def build_nested(parent_object: nil, parent_builder: nil)
      self.requires_save = false
      # parent.send(my_association_name).build
      build
    end

    def update(object_id:)
      self.object = object_class.find_by_id(object_id)
      return {error_status: 404, errors:[{status: 404, code: 'record_not_found'}]} unless object
      assign_parameters_in_transaction
    end

    def permitted_attributes
      self.class._permitted_attributes || []
    end  

    def validator
      return nil unless self.class._validator
      @validator ||= self.class._validator.new(params)
    end

    private

    def assign_parameters_in_transaction
      ActiveRecord::Base.transaction do
        begin
          perform_in_transaction
        rescue => e
          raise_error = -> { raise e }
          rescue_errors(e) || raise_error.call
        ensure
          self.errors = (errors << validator.errors).flatten if validator
          raise ActiveRecord::Rollback unless errors.flatten.empty?
        end  
      end
      Rails.logger.error "Builder Errors:"
      Rails.logger.error errors.to_yaml
      self.object = object.reload if errors.empty? && object.try(:persisted?)
      errors.empty? ? object : {errors: errors, error_status: errors.first[:status]}
    end

    def perform_in_transaction
      self.errors += validator.validate_params.errors if validator
      return false if errors.any?
      self.object = top_level_array || call_setter_for_each_param_key
      return true unless requires_save && !top_level_array
      before_save_callbacks.each { |callback| send(callback) }
      [*object].each(&:save!)
      nested_objects_to_save.flatten.each(&:save!)
      @callback_blocks.each_with_object(object, &:call)
      after_save_callbacks.each { |callback| send(callback) }
    end

    def call_setter_for_each_param_key
      params.each do |key, value|
        send_if_key_included_in_attributes(key.to_sym, value)
      end
      object
    end

    def send_if_key_included_in_attributes(key, value)
      if permitted_attributes.include?(key)
        self.send(key, value)
      else
        errors << {status: 400, message: "Unpermitted parameter key #{key}"}
        raise ActiveRecord::Rollback
      end
    end

    def top_level_array
      return false unless params.is_a?(Array)
      @top_level_array ||= params.map do |param_object|
        self.class.new(param_object, builder_options).build_nested
      end
    end

    #need to use attributes to handle errors that aren't meant to be model methods
    def method_missing(method_name, *args)
      return super unless permitted_attributes.include?(method_name)
      begin
        object.send(:"#{method_name}=", args.first)
      rescue => e
        if params.has_key?(method_name)
          message = "Unable to process value for :#{method_name}, no attribute writer. Be sure to override the automatic setters for all params that do not map straight to a model attribute."
          self.errors << {status: 422, message: message}
        else
          raise e
        end
      end
    end

    def delayed_save!(nested_object)
      self.nested_objects_to_save  = (nested_objects_to_save << nested_object).uniq
    end

    def object_class
      klass = self.class.to_s
      start_position = (/::\w+$/ =~ klass).try(:+,2)
      klass = klass[start_position..-1] if start_position
      suffix_position = klass =~ /Builder$/
      if suffix_position
        try_constant = klass[0...suffix_position]
        begin
          try_constant.constantize
        rescue
          raise NameError.new "#{try_constant} does not exist. Builder class name must map the the name of an existing class"
        end
      else
        raise "#{self.class} must be named ModelNameBuilder to be used as a builder class"
      end
    end

    def rescue_errors(rescued_error)
      raise_if_validation_error(rescued_error)    
      raise_if_argument_error(rescued_error)
      raise_if_unknown_attribute_error(rescued_error)
    end

    def raise_if_validation_error(rescued_error)
      if rescued_error.is_a? ActiveRecord::RecordInvalid
        self.errors << { status: 422, code: 'validation_error', message: rescued_error.message, full_messages: object.errors.full_messages, record: rescued_error.record }
        raise ActiveRecord::Rollback
      end  
    end

    def raise_if_argument_error(rescued_error)
      if rescued_error.is_a? ArgumentError
        message = "All methods on the builder that override attribute setters must accept one argument to catch the parameter value"
        self.errors << { status: 500, code: 'builder_error', message: message }
        raise ArgumentError.new message
      end
    end

    def raise_if_unknown_attribute_error(rescued_error)
      if rescued_error.is_a? ActiveRecord::UnknownAttributeError
        self.errors << { status: 400, code: 'unknown_attribute_error', message: rescued_error.message, record: rescued_error.record }
        raise ActiveRecord::Rollback
      end
    end

    def self.attributes(*args)
      @permitted_attributes ||= []
      args.each { |a| @permitted_attributes << a unless @permitted_attributes.include?(a) }
    end
    
    def self._permitted_attributes
      @permitted_attributes
    end
    
    def validate_params
      message =  "Params passed to builder must be a hash or top level array"
      raise message unless params.respond_to?(:fetch)
      return true if params.is_a? Array
      message = "Params passed to builder must not have a root node"
      key = params.keys.first
      raise message if key && key.to_s.camelize == object_class.to_s
    end

    #used so that id setter is not called by default
    def id(data)
      true
    end

    #######################
    ## callbacks       
    ###########################

    def self.before_save(*args)
      @before_save_callbacks ||= []
      args.each { |a| @before_save_callbacks << a unless @before_save_callbacks.include?(a) }
    end
    
    def self._before_save_callbacks
      @before_save_callbacks
    end
    
    def self._after_save_callbacks
      @after_save_callbacks
    end
    
    def self.after_save(*args)
      @after_save_callbacks ||= []
      args.each { |a| @after_save_callbacks << a unless @after_save_callbacks.include?(a) }
    end
    
    def before_save_callbacks
      self.class._before_save_callbacks || []
    end
    
    def after_save_callbacks
      self.class._after_save_callbacks || []
    end

    def self.validator(validator)
      @validator = validator
    end

    def self._validator
      @validator
    end

    def self.set_adapter(adapter)
      adapter_module = adapter.to_s.camelize.constantize
      self.include adapter_module
      self.extend adapter_module
    end

    def set_params_using_adapter(params)
      self.params = params
      validate_params
    end
  end
end