require 'action_controller/metal/exceptions'

module ActionController #:nodoc:
  class InvalidAuthenticityToken < ActionControllerError #:nodoc:
  end

  # Controller actions are protected from Cross-Site Request Forgery (CSRF) attacks
  # by including a token in the rendered html for your application. This token is
  # stored as a random string in the session, to which an attacker does not have
  # access. When a request reaches your application, \Rails verifies the received
  # token with the token in the session. Only HTML and JavaScript requests are checked,
  # so this will not protect your XML API (presumably you'll have a different
  # authentication scheme there anyway). Also, GET requests are not protected as these
  # should be idempotent.
  #
  # It's important to remember that XML or JSON requests are also affected and if
  # you're building an API you'll need something like:
  #
  #   class ApplicationController < ActionController::Base
  #     protect_from_forgery
  #     skip_before_filter :verify_authenticity_token, :if => :json_request?
  #
  #     protected
  #
  #     def json_request?
  #       request.format.json?
  #     end
  #   end
  #
  # CSRF protection is turned on with the <tt>protect_from_forgery</tt> method,
  # which checks the token and resets the session if it doesn't match what was expected.
  # A call to this method is generated for new \Rails applications by default.
  #
  # The token parameter is named <tt>authenticity_token</tt> by default. The name and
  # value of this token must be added to every layout that renders forms by including
  # <tt>csrf_meta_tags</tt> in the html +head+.
  #
  # Learn more about CSRF attacks and securing your application in the
  # {Ruby on Rails Security Guide}[http://guides.rubyonrails.org/security.html].
  module RequestForgeryProtection
    extend ActiveSupport::Concern

    include AbstractController::Helpers
    include AbstractController::Callbacks

    included do
      # Sets the token parameter name for RequestForgery. Calling +protect_from_forgery+
      # sets it to <tt>:authenticity_token</tt> by default.
      config_accessor :request_forgery_protection_token
      self.request_forgery_protection_token ||= :authenticity_token

      # Controls how unverified request will be handled
      config_accessor :request_forgery_protection_method
      self.request_forgery_protection_method ||= :reset_session

      # Controls whether request forgery protection is turned on or not. Turned off by default only in test mode.
      config_accessor :allow_forgery_protection
      self.allow_forgery_protection = true if allow_forgery_protection.nil?

      helper_method :form_authenticity_token
      helper_method :protect_against_forgery?
    end

    module ClassMethods
      # Turn on request forgery protection. Bear in mind that only non-GET, HTML/JavaScript requests are checked.
      #
      #   class FooController < ApplicationController
      #     protect_from_forgery :except => :index
      #
      # You can disable csrf protection on controller-by-controller basis:
      #
      #   skip_before_filter :verify_authenticity_token
      #
      # It can also be disabled for specific controller actions:
      #
      #   skip_before_filter :verify_authenticity_token, :except => [:create]
      #
      # Valid Options:
      #
      # * <tt>:only/:except</tt> - Passed to the <tt>before_filter</tt> call. Set which actions are verified.
      # * <tt>:with</tt> - Set the method to handle unverified request. Valid values: <tt>:exception</tt> and <tt>:reset_session</tt> (default).
      def protect_from_forgery(options = {})
        self.request_forgery_protection_token ||= :authenticity_token
        self.request_forgery_protection_method = options.delete(:with) if options.key?(:with)
        prepend_before_filter :verify_authenticity_token, options
      end
    end

    protected
      # The actual before_filter that is used. Modify this to change how you handle unverified requests.
      def verify_authenticity_token
        unless verified_request?
          logger.warn "Can't verify CSRF token authenticity" if logger
          handle_unverified_request
        end
      end

      # This is the method that defines the application behavior when a request is found to be unverified.
      # By default, \Rails uses <tt>request_forgery_protection_method</tt> when it finds an unverified request:
      #
      # * <tt>:reset_session</tt> - Resets the session.
      # * <tt>:exception</tt>: - Raises ActionController::InvalidAuthenticityToken exception.
      def handle_unverified_request
        case request_forgery_protection_method
        when :exception
          raise ActionController::InvalidAuthenticityToken
        when :reset_session
          reset_session
        else
          raise ArgumentError, 'Invalid request forgery protection method, use :exception or :reset_session'
        end
      end

      # Returns true or false if a request is verified. Checks:
      #
      # * is it a GET request?  Gets should be safe and idempotent
      # * Does the form_authenticity_token match the given token value from the params?
      # * Does the X-CSRF-Token header match the form_authenticity_token
      def verified_request?
        !protect_against_forgery? || request.get? ||
          form_authenticity_token == params[request_forgery_protection_token] ||
          form_authenticity_token == request.headers['X-CSRF-Token']
      end

      # Sets the token value for the current session.
      def form_authenticity_token
        session[:_csrf_token] ||= SecureRandom.base64(32)
      end

      # The form's authenticity parameter. Override to provide your own.
      def form_authenticity_param
        params[request_forgery_protection_token]
      end

      def protect_against_forgery?
        allow_forgery_protection
      end
  end
end
