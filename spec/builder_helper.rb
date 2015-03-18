# require_relative "../../app/application_services/base_builder"
# require_relative "../../app/application_services/base_params_validator"

class DemoParamsValidator < BaseParamsValidator

  attr_accessor :validated

  def validate_params
    @validated = true
    self
  end

  def errors 
    []
  end

end

class DemoTestBuilder < BaseBuilder
  attributes :name, :content
  before_save :before_one, :before_two
  after_save :after_one
  validator DemoParamsValidator

  def before_one
    object.before_save_called_with_unsaved_object = true unless object.saved
  end

  def before_two; end

  def after_one
    object.after_save_called_with_saved_object = true if object.saved
  end
end

class NoMethodsBuilder < BaseBuilder
  attributes :name, :content
end

class MethodsBuilder < BaseBuilder
  attributes :name, :content
  before_save :before_method
  after_save :after_method
  validator DemoParamsValidator

  def name(data); end

  def content(data); end

  def before_method
    object.before_method_called = true
  end

  def after_method
    object.after_method_called = true
  end
end

class DemoTest
  attr_accessor :name, :content, :author
  attr_reader :saved, :updated
  attr_accessor :before_method_called, :after_method_called
  attr_accessor :before_save_called_with_unsaved_object
  attr_accessor :after_save_called_with_saved_object
  attr_accessor :block_callback_called_after_save

  def save!
    @saved = true
  end

  def update!
    @updated = true
  end

  def self.find_by(argument)
    nil
  end

  def persisted?
    false
  end
end

class PlainValidator; end

class BadValidatorBuilder < BaseBuilder
  validator PlainValidator
end



#Used so that the buidlers with different names can all use the DemoTest class
NoMethods = DemoTest
Methods = DemoTest
BadValidator = DemoTest