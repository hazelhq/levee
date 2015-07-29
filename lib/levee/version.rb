module Levee
  extend self

  VERSION = "0.0.4"

  def gem_description
    %Q(The purpose of the builder object is to create a layer of abstraction between the controller and models in a Rails application. The builder is particularly useful for receiving complex post and put requests with multiple parameters, but is lightweight enough to use for simple writes when some filtering or parameter combination validation might be useful before writing to the database. Since it wraps the entire write action to mulitple models in a single transaction, any failure in the builder will result in the entire request being rolled back.)
  end
end
