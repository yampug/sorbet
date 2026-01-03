require "spec"
require "./sorbet_spec"

describe "Enterprise Production Scenarios" do
  describe "Typed Codebase Scenarios" do
    it "handles typed: false files" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: false
      class UntypedClass
        def untyped_method(x)
          x + 1
        end
      end
      RUBY

      diagnostics = session.typecheck_file("typed_false.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end

    it "handles typed: true files" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: true
      class TypedClass
        def typed_method(x)
          x + 1
        end
      end
      RUBY

      diagnostics = session.typecheck_file("typed_true.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end

    it "handles typed: strict files with signatures" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: strict
      class StrictClass
        extend T::Sig

        sig {params(x: Integer).returns(Integer)}
        def strict_method(x)
          x + 1
        end
      end
      RUBY

      diagnostics = session.typecheck_file("typed_strict.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end

    it "handles typed: strong files" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: strong
      class StrongClass
        extend T::Sig

        sig {params(x: Integer).returns(Integer)}
        def strong_method(x)
          T.let(result = x + 1, Integer)
        end
      end
      RUBY

      diagnostics = session.typecheck_file("typed_strong.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end

    it "detects type errors in strict mode" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: strict
      class StrictTypeError
        extend T::Sig

        sig {params(x: Integer).returns(String)}
        def type_mismatch(x)
          x + 1  # Returns Integer, not String
        end
      end
      RUBY

      diagnostics = session.typecheck_file("strict_type_error.rb", content)
      diagnostics.should_not be_empty

      session.close
    end
  end

  describe "Rails-like Application Structure" do
    it "handles model-like classes with ActiveRecord patterns" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: strict
      class User
        extend T::Sig

        sig {returns(String)}
        attr_accessor :name

        sig {returns(String)}
        attr_accessor :email

        sig {params(name: String, email: String).void}
        def initialize(name, email)
          @name = name
          @email = email
        end

        sig {returns(T::Boolean)}
        def valid?
          !@name.empty? && @email.include?('@')
        end

        sig {returns(String)}
        def display_name
          @name.capitalize
        end
      end
      RUBY

      diagnostics = session.typecheck_file("models/user.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end

    it "handles service objects pattern" do
      session = SorbetSession.new

      user_content = <<-RUBY
      # typed: strict
      class User
        extend T::Sig

        sig {returns(String)}
        attr_reader :email

        sig {params(email: String).void}
        def initialize(email)
          @email = email
        end
      end
      RUBY

      service_content = <<-RUBY
      # typed: strict
      require_relative 'user'

      class UserRegistrationService
        extend T::Sig

        sig {params(email: String, password: String).returns(T.nilable(User))}
        def self.register(email, password)
          return nil if email.empty? || password.length < 8

          user = User.new(email)
          # In real app: save to database, send email, etc.
          user
        end

        sig {params(user: User).returns(T::Boolean)}
        def self.send_welcome_email(user)
          # In real app: send email
          true
        end
      end
      RUBY

      File.write("user.rb", user_content)

      session.typecheck_file("user.rb", user_content)
      diagnostics = session.typecheck_file("user_registration_service.rb", service_content)

      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
      TestHelper.cleanup_file("user.rb")
    end

    it "handles controller-like classes" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: true
      class UsersController
        extend T::Sig

        sig {params(params: T::Hash[String, T.untyped]).returns(String)}
        def index(params)
          # In real app: fetch from database
          "User list"
        end

        sig {params(id: Integer).returns(T.nilable(String))}
        def show(id)
          return nil if id <= 0

          # In real app: fetch from database
          "User \#{id}"
        end

        sig {params(params: T::Hash[String, T.untyped]).returns(T::Boolean)}
        def create(params)
          email = params["email"]
          return false unless email.is_a?(String)

          # In real app: create user
          true
        end
      end
      RUBY

      diagnostics = session.typecheck_file("controllers/users_controller.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end
  end

  describe "API Client Scenarios" do
    it "handles HTTP client wrapper with typed responses" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: strict
      class APIResponse
        extend T::Sig

        sig {returns(Integer)}
        attr_reader :status

        sig {returns(T::Hash[String, T.untyped])}
        attr_reader :body

        sig {params(status: Integer, body: T::Hash[String, T.untyped]).void}
        def initialize(status, body)
          @status = status
          @body = body
        end

        sig {returns(T::Boolean)}
        def success?
          @status >= 200 && @status < 300
        end
      end

      class APIClient
        extend T::Sig

        sig {params(endpoint: String).returns(APIResponse)}
        def get(endpoint)
          # In real app: make HTTP request
          APIResponse.new(200, {"data" => "response"})
        end

        sig {params(endpoint: String, data: T::Hash[String, T.untyped]).returns(APIResponse)}
        def post(endpoint, data)
          # In real app: make HTTP request
          APIResponse.new(201, {"created" => true})
        end

        sig {params(response: APIResponse).returns(T.nilable(String))}
        def extract_error(response)
          return nil if response.success?

          response.body["error"]&.to_s
        end
      end
      RUBY

      diagnostics = session.typecheck_file("lib/api_client.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end
  end

  describe "Dependency Injection and Interfaces" do
    it "handles interface definitions with abstract methods" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: strict
      module PaymentProcessor
        extend T::Sig
        extend T::Helpers

        interface!

        sig {abstract.params(amount: Integer).returns(T::Boolean)}
        def process_payment(amount); end

        sig {abstract.params(transaction_id: String).returns(T::Boolean)}
        def refund(transaction_id); end
      end

      class StripeProcessor
        extend T::Sig
        include PaymentProcessor

        sig {override.params(amount: Integer).returns(T::Boolean)}
        def process_payment(amount)
          # Process via Stripe
          amount > 0
        end

        sig {override.params(transaction_id: String).returns(T::Boolean)}
        def refund(transaction_id)
          # Refund via Stripe
          !transaction_id.empty?
        end
      end

      class PayPalProcessor
        extend T::Sig
        include PaymentProcessor

        sig {override.params(amount: Integer).returns(T::Boolean)}
        def process_payment(amount)
          # Process via PayPal
          amount > 0
        end

        sig {override.params(transaction_id: String).returns(T::Boolean)}
        def refund(transaction_id)
          # Refund via PayPal
          !transaction_id.empty?
        end
      end
      RUBY

      diagnostics = session.typecheck_file("payment_processor.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end
  end

  describe "Generic Types and Collections" do
    it "handles generic type parameters" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: strict
      class Repository
        extend T::Sig
        extend T::Generic

        Elem = type_member

        sig {void}
        def initialize
          @items = T.let([], T::Array[Elem])
        end

        sig {params(item: Elem).void}
        def add(item)
          @items << item
        end

        sig {returns(T::Array[Elem])}
        def all
          @items
        end

        sig {params(id: Integer).returns(T.nilable(Elem))}
        def find(id)
          @items[id]
        end
      end

      class User
        extend T::Sig

        sig {returns(String)}
        attr_reader :name

        sig {params(name: String).void}
        def initialize(name)
          @name = name
        end
      end

      class UserRepository < Repository
        extend T::Sig
        Elem = type_member {{fixed: User}}
      end
      RUBY

      diagnostics = session.typecheck_file("generic_repository.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end

    it "handles complex type unions" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: strict
      class Result
        extend T::Sig

        sig {params(value: T.any(String, Integer, T::Array[String])).returns(String)}
        def self.format(value)
          case value
          when String
            value
          when Integer
            value.to_s
          when Array
            value.join(", ")
          else
            T.absurd(value)
          end
        end

        sig {params(data: T.nilable(String)).returns(String)}
        def self.unwrap_or_default(data)
          data || "default"
        end
      end
      RUBY

      diagnostics = session.typecheck_file("result.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end
  end

  describe "Large Codebase Simulation" do
    it "handles multi-file application with interdependencies" do
      session = SorbetSession.new

      files = {} of String => String

      # Base classes
      files["lib/base_model.rb"] = <<-RUBY
      # typed: strict
      class BaseModel
        extend T::Sig

        sig {returns(Integer)}
        attr_reader :id

        sig {params(id: Integer).void}
        def initialize(id)
          @id = id
        end

        sig {returns(T::Boolean)}
        def valid?
          @id > 0
        end
      end
      RUBY

      # Domain models
      files["models/product.rb"] = <<-RUBY
      # typed: strict
      require_relative '../lib/base_model'

      class Product < BaseModel
        extend T::Sig

        sig {returns(String)}
        attr_reader :name

        sig {returns(Float)}
        attr_reader :price

        sig {params(id: Integer, name: String, price: Float).void}
        def initialize(id, name, price)
          super(id)
          @name = name
          @price = price
        end

        sig {override.returns(T::Boolean)}
        def valid?
          super && !@name.empty? && @price > 0.0
        end
      end
      RUBY

      files["models/order.rb"] = <<-RUBY
      # typed: strict
      require_relative '../lib/base_model'
      require_relative 'product'

      class Order < BaseModel
        extend T::Sig

        sig {returns(T::Array[Product])}
        attr_reader :products

        sig {params(id: Integer).void}
        def initialize(id)
          super(id)
          @products = T.let([], T::Array[Product])
        end

        sig {params(product: Product).void}
        def add_product(product)
          @products << product if product.valid?
        end

        sig {returns(Float)}
        def total
          @products.sum(&:price)
        end
      end
      RUBY

      # Services
      files["services/order_service.rb"] = <<-RUBY
      # typed: strict
      require_relative '../models/order'
      require_relative '../models/product'

      class OrderService
        extend T::Sig

        sig {params(order_id: Integer, product_ids: T::Array[Integer]).returns(Order)}
        def self.create_order(order_id, product_ids)
          order = Order.new(order_id)

          product_ids.each do |pid|
            # In real app: fetch from database
            product = Product.new(pid, "Product \#{pid}", 10.0 * pid)
            order.add_product(product)
          end

          order
        end

        sig {params(order: Order).returns(T::Boolean)}
        def self.process(order)
          return false unless order.valid?
          return false if order.total <= 0.0

          # In real app: process payment, update inventory, etc.
          true
        end
      end
      RUBY

      # Write files to disk for proper require_relative
      files.each do |path, content|
        dir = File.dirname(path)
        Dir.mkdir_p(dir) unless Dir.exists?(dir)
        File.write(path, content)
      end

      # Typecheck all files
      diagnostics = session.typecheck_files_batch(files)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close

      # Cleanup
      files.keys.each { |f| TestHelper.cleanup_file(f) }
      ["lib", "models", "services"].each do |dir|
        Dir.delete(dir) if Dir.exists?(dir) && Dir.children(dir).empty?
      end
    end

    it "handles configuration and settings classes" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: strict
      class AppConfig
        extend T::Sig

        sig {returns(String)}
        attr_reader :database_url

        sig {returns(Integer)}
        attr_reader :port

        sig {returns(String)}
        attr_reader :environment

        sig {returns(T::Boolean)}
        attr_reader :debug_mode

        sig {void}
        def initialize
          @database_url = T.let(ENV.fetch("DATABASE_URL", "postgres://localhost"), String)
          @port = T.let(ENV.fetch("PORT", "3000").to_i, Integer)
          @environment = T.let(ENV.fetch("RAILS_ENV", "development"), String)
          @debug_mode = T.let(@environment == "development", T::Boolean)
        end

        sig {returns(T::Boolean)}
        def production?
          @environment == "production"
        end

        sig {returns(T::Boolean)}
        def development?
          @environment == "development"
        end

        sig {returns(T::Hash[Symbol, T.untyped])}
        def to_h
          {
            database_url: @database_url,
            port: @port,
            environment: @environment,
            debug_mode: @debug_mode
          }
        end
      end
      RUBY

      diagnostics = session.typecheck_file("config/app_config.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end
  end

  describe "Error Handling Patterns" do
    it "handles Result/Either pattern" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: strict
      class Success
        extend T::Sig
        extend T::Generic

        Value = type_member

        sig {returns(Value)}
        attr_reader :value

        sig {params(value: Value).void}
        def initialize(value)
          @value = value
        end

        sig {returns(T::Boolean)}
        def success?
          true
        end
      end

      class Failure
        extend T::Sig

        sig {returns(String)}
        attr_reader :error

        sig {params(error: String).void}
        def initialize(error)
          @error = error
        end

        sig {returns(T::Boolean)}
        def success?
          false
        end
      end

      class UserValidator
        extend T::Sig

        sig {params(email: String).returns(T.any(Success[String], Failure))}
        def self.validate_email(email)
          if email.include?('@')
            Success[String].new(email)
          else
            Failure.new("Invalid email format")
          end
        end
      end
      RUBY

      diagnostics = session.typecheck_file("patterns/result.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end
  end

  describe "Background Job Patterns" do
    it "handles job classes with typed perform methods" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: strict
      class EmailJob
        extend T::Sig

        sig {params(user_email: String, subject: String, body: String).void}
        def self.perform(user_email, subject, body)
          # In real app: send email via SMTP or email service
          puts "Sending email to \#{user_email}: \#{subject}"
        end

        sig {params(user_email: String, subject: String, body: String, delay: Integer).void}
        def self.perform_later(user_email, subject, body, delay)
          # In real app: enqueue job
          sleep(delay)
          perform(user_email, subject, body)
        end
      end

      class DataProcessingJob
        extend T::Sig

        sig {params(data_ids: T::Array[Integer]).void}
        def self.perform_batch(data_ids)
          data_ids.each do |id|
            # In real app: process data
            puts "Processing data \#{id}"
          end
        end
      end
      RUBY

      diagnostics = session.typecheck_file("jobs/email_job.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end
  end

  describe "Middleware and Chain of Responsibility" do
    it "handles middleware pattern" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: strict
      class Request
        extend T::Sig

        sig {returns(T::Hash[String, T.untyped])}
        attr_accessor :data

        sig {void}
        def initialize
          @data = T.let({}, T::Hash[String, T.untyped])
        end
      end

      module Middleware
        extend T::Sig
        extend T::Helpers

        interface!

        sig {abstract.params(request: Request).returns(Request)}
        def call(request); end
      end

      class AuthenticationMiddleware
        extend T::Sig
        include Middleware

        sig {override.params(request: Request).returns(Request)}
        def call(request)
          request.data["authenticated"] = true
          request
        end
      end

      class LoggingMiddleware
        extend T::Sig
        include Middleware

        sig {override.params(request: Request).returns(Request)}
        def call(request)
          puts "Request: \#{request.data}"
          request
        end
      end

      class MiddlewareChain
        extend T::Sig

        sig {void}
        def initialize
          @middlewares = T.let([], T::Array[Middleware])
        end

        sig {params(middleware: Middleware).void}
        def use(middleware)
          @middlewares << middleware
        end

        sig {params(request: Request).returns(Request)}
        def execute(request)
          @middlewares.reduce(request) { |req, middleware| middleware.call(req) }
        end
      end
      RUBY

      diagnostics = session.typecheck_file("middleware/chain.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end
  end
end
