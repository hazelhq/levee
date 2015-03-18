require_relative './builder_helper.rb'

#Base builder is an abstract class. A test class is made in /spec/support/test_builder.rb that defines 
#a concrete child class.

describe 'BaseBuidler' do
  let(:demo_class) { DemoTest }
  let(:params) { {name: 'test params',
                  content: 'none'} }
  subject { DemoTestBuilder.new(params) }

  describe 'initialization' do
    it 'sets requires_save to true' do
      expect(subject.requires_save).to be 
    end
  end

  describe '#build' do
    let(:object_class) { double(find_by: nil) }
    before do 
      allow(object_class).to receive(:new) { demo_class.new }
      allow(subject).to receive(:object_class) { object_class  }
      allow(subject).to receive(:assign_parameters_in_transaction)
    end

    context 'when the parameters are a top level array' do
      it 'calls #assign_parameters_in_transaction' do
        subject.params = []
        expect(subject).to receive(:assign_parameters_in_transaction)
        subject.build
      end
    end

    context 'when the parameters are an object that contains an id' do
      before { subject.params[:id] = 4 }

      it 'class #find_by on #object class with params[:id]' do
        expect(object_class).to receive(:find_by).with({id: subject.params[:id]})
        subject.build
      end
    end

    context 'when the parameters are an object that does not contain an id' do

      it 'calls #object_class' do
        expect(subject).to receive(:object_class)
        subject.build
      end

      it 'assigns a newly instantiated object of object_class to builder#object' do
        allow(subject).to receive(:assign_parameters_in_transaction)
        subject.build
        expect(subject.object).to be_a demo_class 
      end
    end
  end

  describe 'build_nested' do
    before do 
      allow(subject).to receive(:build)
    end

    it 'sets #requires_save to false' do
      expect(subject).to receive(:requires_save=).with(false)
      subject.build_nested
    end

    it 'calls #build' do
      expect(subject).to receive(:build)
      subject.build_nested
    end
  end

  describe 'update(object_id:, acting_user=nil' do
    context 'when the object can\'t be found' do
      it 'returns an errors hash with the error status 404' do
        object_class = double(find_by_id: nil)
        allow(subject).to receive(:object_class) {object_class}
        result = subject.update(object_id: 0)
        expect(result[:error_status]).to eq(404) 
      end
    end  

    context 'when an object is found' do
      before do
        object_class = double(find_by_id: :found_object)
        allow(subject).to receive(:object_class) {object_class}
      end

      it 'assigns the found object to the builder\'s object attribute' do
        expect(subject).to receive(:object=).with(:found_object)
        subject.update(object_id: 0)
      end

      it 'calls #assign_parameters_in_transaction' do
        expect(subject).to receive(:assign_parameters_in_transaction)
        subject.update(object_id: 0)
      end
    end
  end

  context 'when the params have a root node' do
    it 'throws an exception' do
      expect { DemoTestBuilder.new({demo_test: 'gg'}) }.to raise_error
    end
  end

  describe '#permitted_attributes' do
    context 'when the attributes method is called in the class definition with attribute symbols as parameter' do
      it 'those attribute symbols are available in #permitted_attributes' do
        expect(DemoTestBuilder.new({}).permitted_attributes).to include :name
        expect(DemoTestBuilder.new({}).permitted_attributes).to include :content
      end
    end

    context 'when params are passed that are not permitted at class definition' do
      it 'does not include those in the #permitted_attributes' do
        expect(DemoTestBuilder.new({}).permitted_attributes).to_not include :author
      end
    end
  end 

  describe 'matching param keys to attributes' do
    let(:unpermitted_params) { {name: 'test params',
                                content: 'none',
                                author: 'Jim'} }
    it 'saves the object' do
      builder = NoMethodsBuilder.new params
      builder.build
      expect(builder.object.saved).to be
    end

    it 'does not save the object if a param key is included that is not listed as a permitted attribute' do
      builder = NoMethodsBuilder.new unpermitted_params
      builder.build
      expect(builder.object.saved).to_not be
    end

    context 'when there are no custom methods defined that match param keys' do
      specify "For each param key that is included in permitted attributes, the value of the param is assigned to the object\'s attribute matching the key name" do
        builder = NoMethodsBuilder.new params
        builder.build
        expect(builder.object.name).to eq(params[:name])
        expect(builder.object.content).to eq(params[:content])
        expect(builder.object.author).to_not be 
      end
    end

    context 'when there are custom methods defined that match the name of attributes' do
      specify 'those attributes are not automatically assigned' do
        builder = MethodsBuilder.new params
        builder.build
        expect(builder.object.name).to_not be
        expect(builder.object.content).to_not be
        expect(builder.object.author).to_not be 
      end
    end
  end 

  describe '#top_level_array' do
    let(:array_params) { [params,params] }
    subject { DemoTestBuilder.new(array_params) }

    context 'when the params contain an array of two objects' do
      it 'returns two objects' do
        result = subject.send(:top_level_array)
        expect(result[0]).to be_a DemoTest 
        expect(result[1]).to be_a DemoTest 
      end

      it 'does not save the objects' do
        result = subject.send(:top_level_array)
        expect(result[0].saved).to_not be
      end
    end
  end

  describe 'delayed_save!(object)' do
    it 'adds the object to the #nested_objects_to_save array' do
      expect(subject.nested_objects_to_save).to be_a Array
      subject.send(:delayed_save!, :nested_object)
      expect(subject.nested_objects_to_save).to include :nested_object 
    end    

    it 'does not add an duplicate object' do
      expect(subject.nested_objects_to_save.length).to be 0
      subject.send(:delayed_save!, 'nested_object')
      subject.send(:delayed_save!, 'nested_object')
      expect(subject.nested_objects_to_save.length).to be 1
    end
  end

  describe 'callbacks' do
    context 'when the before_save method is used in the class definition' do
      it 'adds the method symbols passed to the #before_save_callbacks array' do
        expect(subject.send(:before_save_callbacks)).to match_array [:before_one, :before_two] 
      end
    end

    context 'when the after_save method is used in the class definition' do
      it 'adds the method symbols passed to the #after_save_callbacks array' do
        expect(subject.send(:after_save_callbacks)).to match_array [:after_one] 
      end
    end
  end

  describe 'building the object' do
    context '#assign_parameters_in_transaction' do

      context 'when there is a validator assigned' do
        it 'calls #validate_parameters on the validator' do
          subject.build
          expect(subject.validator.validated).to be
        end
      end

      context 'when the validator returns errors' do
        let(:error) { error = {status: 400, code: 'invalid_request_error'} }
        before { allow(subject.validator).to receive(:errors) { [error] } }

        it 'the method returns early, not calling the following methods' do
          expect(subject).to_not receive(:top_level_array)  
        end

        it 'returns an errors hash' do
          expect(subject.build[:errors]).to be 
        end
      end

      it '#calls top_level_array' do
        expect(subject).to receive(:top_level_array).at_least(:once) 
        subject.build
      end

      it 'calls #call_setter_for_each_param_key' do
        expect(subject).to receive(:assign_parameters_in_transaction).at_least(:once) 
        subject.build
      end

      context 'when there are no errors' do  
        context 'when #requires_save is truthy' do
          it 'saves the object' do
            subject.build
            expect(subject.object.saved).to be 
          end  

          it 'calls save on all #nested_objects_to_save' do
            nest1 = double
            nest2 = double
            expect(nest1).to receive(:save!)
            expect(nest2).to receive(:save!)
            subject.nested_objects_to_save = [ nest1, nest2 ]
            subject.build
          end

          it 'calls the #before_save_callbacks before the object is saved' do
            subject.build
            expect(subject.object.before_save_called_with_unsaved_object).to be
          end

          it 'calls @after_save_callbacks after object is saved' do
            subject.build
            expect(subject.object.after_save_called_with_saved_object).to be 
          end

          it 'calls callback blocks after object is saved' do
            subject = DemoTestBuilder.new(params) { |object| object.block_callback_called_after_save = true if object.saved }
            subject.build
            expect(subject.object.block_callback_called_after_save).to be 
          end
        end
        
        context 'when #requires_save is falsey' do
          it 'does not save the object' do
            subject.build_nested
            expect(subject.object.saved).to_not be 
          end  
        end
      end
  
      context 'when there are errors' do
        
      end
    end
  end

  describe 'self.validator' do
    context 'when called with a validator class name' do
      it 'adds that validator to the #validator method' do
        expect(subject.validator).to be_a DemoParamsValidator 
      end

      it 'raises an exception if the class given is not a BaseParamsValidator' do
        
      end
    end
  end

  describe '#validator' do
    it 'returns a BaseParamsValidator' do
      expect(subject.validator).to be_a BaseParamsValidator
    end

    it 'returns an object that responds to #params and returns some data' do
      expect(subject.validator.params).to be 
    end
  end
end


