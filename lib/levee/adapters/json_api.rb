module JsonApi

  def included
    @included
  end

  def included=(v)
    @included = v
  end

  def set_params_using_adapter(params)
    self.params = params[:data]
    self.included = params[:included]
    validate_params 
    validate_included
  end

  def validate_params
    message =  "Params passed to a builder using :json_api adapter must be a hash with the root_node data"
    raise message unless params.respond_to?(:fetch)
    return true if params.is_a? Array
    message = "Params passed to builder must not have a root node"
    key = params.keys.first
    raise message if key && key.to_s.camelize == object_class.to_s
  end

  def validate_included
    message =  "Params passed to builder must be a hash"
    raise message unless params.respond_to?(:fetch)
    return true if params.is_a? Array
    message = "Params passed to builder must not have a root node"
    key = params.keys.first
    raise message if key && key.to_s.camelize == object_class.to_s
  end

end