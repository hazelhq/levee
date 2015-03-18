# Levee

TODO: Write a gem description

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'levee'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install levee

## Usage

Overview
------------------------

The abstract builder and validator classes are abstract classes for concrete builder classes to inherit from.
The purpose of the builder object is to create a layer of abstraction between the controller and models in a Rails application. 

The builder is particularly useful for receiving complex post and put requests with multiple parameters, but is lightweight enough to use for simple writes when some filtering or parameter combination validation might be useful before writing to the database. Since it wraps the entire write action to mulitple models in a single transaction, any failure in the builder will result in the entire request being rolled back. 


Features
----------------------


- Entire build action wrapped in transaction by default
- Automatic rollback if errors present
- Lightwight, flexible DSL that can be easily overridden or extended
- Macro-style validators
- Transaction-level callbacks
- Automatic generation of errors object
- Mass-assignment protection, parameter whitelisting outside of controller
- Find-or-instantiate based on class name inference



The TL;DR copy & paste version:
---------------------------------


Save this somewhere in your app directory. Maybe in a builders folder?


      class PostBuilder < Levee::Builder
        #matches the class name

        #make sure you list all params that are passed in (you can skip id if you want)
        attributes :title,
                   :content,
                   :tweet_required,
                   :author,
                   :comment

        #list as many before_save and after_save callbacks as you want
        after_save :tweet_post

        #choose a validator class to run automatically (must be a legit levee validator class)
        validator PostParamsValidator

        #access the model using #object
        #this method is completely redundant
        #it is what is called if you don't define a method for a listed attribute
        def title(data)
          object.title = data
        end

        #override the automatic writer so it doesn't try to set it on object
        #needs to take exactly one parameter
        def tweet_required(data); end


        #use #delayed_save be be sure the object is saved after the parent object
        def comment(data)
          comment = Comment.new(content: data, author: current_user)
          object.comments << comment
          delayed_save!(comment)
        end

        private

        #get data that you passed in in the builder_options hash
        def current_user
          @current_user ||= User.find(builder_options[:user_id])
        end

        #access the params you passed in anywhere you need to 
        def tweet_post
          TwitterMachine.spam(object) if params[:tweet_required]
        end
      end


######These are the methods you have access to inside the builder:

      :params
      :errors                  #Array
      :object                  #ActiveRecord::Base
      :permitted_attributes    #Array
      :requires_save           #Boolean
      :builder_options         #Hash

    


The Full Deets on What is Going on Here:
------------------------------------


The API is for the builder is intended to closely resemble that of ActiveModel::Serializers, as the builder is used in a way similar way but for parsing data into instead of serializing data out of Rails models. 



Creating a Builder
==================================


Each builder class inherits from BaseBuilder and maps directly onto one ActiveRecord model. The model name is inferred from the builder name, so for a Post model builder must be named PostBuilder. Class inference works with namespaced builders as well, leveraging the magic of regex voodoo. Currently there is no way to use a builder with a non-matching model. 


###Attribute Mapping and Whitelisting


All parameters that are used within the builder must be explicitly whitelisted as attributes. This can either provide super-reduntant mass-assignment protection on top of the Rails strong params or can be used in place of them to stop param whitelisting from ruining your short controller zen. Because the builder iteratively assigns each parmeter using the attribute writers you can pass paremters from the controller without whitelisting them there if you prefer. See 'Using the Builder' below for more on how to work with the rails params hash. 

By default, the builder will attempt to map every parameter onto the attribute writer on the target model with the same name. If parameters are passed that are not whitelisted an exception will be raised. In order to implement custom behaviour for certain parmeters, methods written inside the class will be called when they match the name of whitelisted attribute that receives data from the params. These overwriter methods must take one parameter, which will hold the value of the submitted parameter. When an automatic attribute method is overridden by a custom method, the return value of the method does not map to the matching attribute writer


Let me say that again. The return value of custom methods does not automatically map to the matchiang attribute writer. Anytime a default mapping is overridden, you are left with full flexibility to do what you want with the parameter value, including throw it away. This allows to builder to utilize parameters that were never intended to be written straight as model data. For parameter values that you want to throw away or handle elsewhere inside the builder, simply define a for the parameter key name that does nothing. To make it explicit that it is intentionally empty, write in like this: ``def parameter_key_name(value); end``


#####A note on :id

The id key is the only key in the params hash that does not need to be whitelisted and will not be mapped by default. It can still be overridden if you want to catch the id and do someting with it, or if you want to cue some other action just before the attribute mapping executes.


###The object object


As in ActiveModel::Serializers, the builder makes use of the object object within the class. This allows for code that easily reusable between create and update requests. Behind the scenes the base builder uses the id the the params hash to look up the existing object form the inferred model and represents it as object. If no :id parameter exists a new empty object of that class is instantiated and assigned to object. Buidler methods then don't need to know or care about whether object is new or existing and can treat it the same. In the cases where this might be important, you are of course free to dig into object and ask it all sorts of ActiveRecord questions about its state inside your overwriter methods. 


Just like you use object in your serializer methods to query things about the object. Use object in your builder methods to call methods on objects or set values. This can be super useful when you want to so something like initiate changes to a state machine while maintaining a RESTful web interface. Changes to state can be included in an update action, then the builder can check for the paremeters used for initiating a state change and call methods on object (or anywhere else really). Once again, the return values of the builder methods are thrown away and are completely unimportant. 


Using the Builder
======================================


Currently the builder name is not inferred from the controller name and it msut be called explicitly in the controller. On initialization the builder takes the params as a mandatory first argument for parmas, a number of optional keyword arguments and an optional block. The block is used to quickly assign a single :after_save callback from data that is available in the controller. 

The builder does not expect to get the entire params hash in the controller but instead wants a hash or array with no root node. When making a new post, for example, you would call ``PostBuilder.new(params[:post])``. This means that you have the choice of whether you whitelist in the controller using Rails strong params or pass the raw params in. The builder will force you to whitelist them inside regardless. 

The builder will throw an exception on initialization if you pass it something besides an array or hash as the params, or if the params have a root node matching the class name. It won't creating the regular errors hash, because the client shouldn't be exposed to this error message. Any extra stuff in the params should be filtered out by the controller. 



###The Builder#build method


The build method fires the the entire builder for both create and update. Two other public methods are also available. #build_nested will perform the build without saving. In doing so it completely skips the callbacks so use it carefully. #update is used for explicitly passing in :object_id at initialization that will take precedence over any id value that is included in the parameters. This can be used if you watch to ensure that an id from the query string params is used instead of the request body. 


The build method returns either the ActiveRecord object or an errors hash. Expected errors will be rescued and added to the errors hash, where unexpected errors will be raised. In both cases the entire build transaction will be rolled back. 




Moar Features
======================================


###Callbacks


You can list macro-style callbacks inside the class just like in your ActiveRecord models. 

      class PostBuilder < Levee::Builder

        attributes :title,
                   :content,
                   :author

        before_save :update_state

        after_save :add_email_job,
                   :count_records

        def update_state
        end

        def add_email_job
        end

        #you get the idea

      end

Just be sure you define the methods you list somewhere within the class, otherwise you get an explosion. An important point to remember is that callbacks ARE NOT CALLED EVER if you use the #build_nested instead of the #build method. 


### #delayed_save(object)



The builder implements #delayed_saved(object) to be used inside a builder class. This is a shortcut for calling save! on any object as part of the after save callbacks. It is useful for when you are creating nested objects inside a builder and you want to be sure that the parent object is saved first, as is the case with associations where you need to be sure the parent has all attributes in place to pass validattion before the child forces a save. Note that delayed_save callbacks fire before the rest of the after_save callbacks.


      class PostBuilder < Levee::Builder

        attributes :title,
                   :content,
                   :author
                   :comment

        def comment(data)
          new_comment = Comment.new(content: data)
          object.comments < new_comment
          delayed_save!(new_comment)
        end
      end      


###Builder Options


You probably have situations where you want to get stuff from the controller inside the builder that doesn't come in the params. You can include any number of keyword arguments after the parameters argument at initialization that will be available inside the builder in the ``builder options`` hash. 


When you make the builder like this in the contoller: ``PostBuilder.new(params[:post], user: current_user).build``


Inside the builder you can get the current user by calling ``builder_options[:current_user]``


This way you can easily pass in any extra query string stuff you get in the params. It's recommended that you perform any lookups inside a method in the builder instead of in the controller when you don't need to reuse them for anything out there. For example, if you only need the current user in the builder, pass in the user_id from the query string params and define a method like this in your builder:


      def user
        @user ||= User.find(builder_options[:user_id])
      end


That way the controller stays nice and snappy and the builder has a reusable method that's not 30 chars long.


###Validator


You can make a validator class to be used with your builder. It's a good place to do validations that check for certain combinations of parameters, especially if they affect multiple models and therefore don't really make sense to have in one model class or the other. The validator uses only a tiny bit of custom syntax, and it's really just there to make your life easier. 


#####Make the validator:


Make the class like this. You can put it anywhere in the app directory, but it feels very at home in a folder called validations. It doesn't use class inference so you can call it whatever


      class UltraSweetValidator < Levee::Validator
    
        validations :first_method,
                    :other_method

        def first_method
          if params[:a_thing]
            return true if params[:that_other_thing_that_has_to_be_there]
          else
            message "You can't do that"
            add_invalid_request_error(message)
          end          
        end

        def other_method
          #return value doesn't matter
        end
      end


Just list all the validation methods you want at the top and then define them below. The builder knows how to call them. The validator has access to two useful objects and has one useful custom method. You can, obviously, access the params that you passed into the builder (not the ones in the controller), and you can also access the errors hash. 


When you find something you don't like, you can either use the super userful #add_invalid_request_error(message) method, or you can just add whatever you want to the errors hash. If the errors hash is anyting but completely empty the buidler transaction will roll back and return whatever is in there to the controller. The method just adds your message there is a nice formatted way and includes a 400 'bad request' status code. If you want to skip the the rest of the validations as soon as one fails just add a bang (!) to the end of the method. Don't add it after the message argument, that would obviously be wrong.


#####Use the validator:


Call the validator inside the builder by listing the class name 


      class PostBuilder < Levee::Builder

        attributes :title,
                   :content,
                   :author
                   :comment

        validator UltraSweetValidator

      end


That's it. The validator is called at the very beginning of the build method (and the other similar ones) and if it snags any errors in the errors hash it will return them instead of trying to run the rest of the build action. If all goes well, this will give you a way to stop your builder from exploding because it's missing data it expects to be there. The validators are there to keep messy error handling out of the builders. You should definitely use them. 


Don't bother validating simple params in your validator that map straight onto the model attributes. The builder always calls #save! instead of #save and then catches the errors so you can jsut use your regular old ActiveRecord validators and still have a errors hash at the end. 



## Contributing

1. Fork it ( https://github.com/[my-github-username]/levee/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
