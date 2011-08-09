require "fileutils"
require 'mimetype_fu'
require "attachment_magic/version"
require "attachment_magic/backends/file_system_backend"

module AttachmentMagic
  @@content_types      = [
    'image/jpeg',
    'image/pjpeg',
    'image/jpg',
    'image/gif',
    'image/png',
    'image/x-png',
    'image/jpg',
    'image/x-ms-bmp',
    'image/bmp',
    'image/x-bmp',
    'image/x-bitmap',
    'image/x-xbitmap',
    'image/x-win-bitmap',
    'image/x-windows-bmp',
    'image/ms-bmp',
    'application/bmp',
    'application/x-bmp',
    'application/x-win-bitmap',
    'application/preview',
    'image/jp_',
    'application/jpg',
    'application/x-jpg',
    'image/pipeg',
    'image/vnd.swiftview-jpeg',
    'image/x-xbitmap',
    'application/png',
    'application/x-png',
    'image/gi_',
    'image/x-citrix-pjpeg'
  ]
  mattr_reader :content_types, :tempfile_path
  mattr_writer :tempfile_path

  class ThumbnailError < StandardError;  end
  class AttachmentError < StandardError; end

  def self.tempfile_path
    @@tempfile_path ||= Rails.root.join('tmp', 'attachment_magic')
  end

  module ActMethods
    # Options:
    # *  <tt>:content_type</tt> - Allowed content types.  Allows all by default.  Use :image to allow all standard image types.
    # *  <tt>:min_size</tt> - Minimum size allowed.  1 byte is the default.
    # *  <tt>:max_size</tt> - Maximum size allowed.  1.megabyte is the default.
    # *  <tt>:size</tt> - Range of sizes allowed.  (1..1.megabyte) is the default.  This overrides the :min_size and :max_size options.
    # *  <tt>:path_prefix</tt> - path to store the uploaded files.  Uses public/#{table_name} by default.
    # *  <tt>:storage</tt> - Use :file_system to specify the attachment data is stored with the file system.  Defaults to :file_system.
    #
    # Examples:
    #   has_attachment :max_size => 1.kilobyte
    #   has_attachment :size => 1.megabyte..2.megabytes
    #   has_attachment :content_type => 'application/pdf'
    #   has_attachment :content_type => ['application/pdf', 'application/msword', 'text/plain']
    def has_attachment(options = {})
      # this allows you to redefine the acts' options for each subclass, however
      options[:min_size]         ||= 1
      options[:max_size]         ||= 1.megabyte
      options[:size]             ||= (options[:min_size]..options[:max_size])
      options[:content_type] = [options[:content_type]].flatten.collect! { |t| t == :image ? AttachmentMagic.content_types : t }.flatten unless options[:content_type].nil?

      extend ClassMethods unless (class << self; included_modules; end).include?(ClassMethods)
      include InstanceMethods unless included_modules.include?(InstanceMethods)

      parent_options = attachment_options || {}
      # doing these shenanigans so that #attachment_options is available to processors and backends
      self.attachment_options = options

      attachment_options[:storage]     ||= :file_system
      attachment_options[:storage]     ||= parent_options[:storage]
      attachment_options[:path_prefix] ||= attachment_options[:file_system_path]
      if attachment_options[:path_prefix].nil?
        File.join("public", table_name)
      end
      attachment_options[:path_prefix]   = attachment_options[:path_prefix][1..-1] if options[:path_prefix].first == '/'

      unless File.directory?(AttachmentMagic.tempfile_path)
        FileUtils.mkdir_p(AttachmentMagic.tempfile_path)
      end

      storage_mod = AttachmentMagic::Backends.const_get("#{options[:storage].to_s.classify}Backend")
      include storage_mod unless included_modules.include?(storage_mod)

    end

    def load_related_exception?(e) #:nodoc: implementation specific
      case
      when e.kind_of?(LoadError), e.kind_of?(MissingSourceFile), $!.class.name == "CompilationError"
        # We can't rescue CompilationError directly, as it is part of the RubyInline library.
        # We must instead rescue RuntimeError, and check the class' name.
        true
      else
        false
      end
    end
    private :load_related_exception?
  end

  module ClassMethods
    delegate :content_types, :to => AttachmentMagic

    # Performs common validations for attachment models.
    def validates_as_attachment
      validates_presence_of :size, :content_type, :filename
      validate              :attachment_attributes_valid?
    end

    # Returns true or false if the given content type is recognized as an image.
    def image?(content_type)
      content_types.include?(content_type)
    end

    def self.extended(base)
      base.class_inheritable_accessor :attachment_options
      base.before_validation :set_size_from_temp_path
      base.after_save :after_process_attachment
      base.after_destroy :destroy_file
      base.after_validation :process_attachment
    end

    # Copies the given file path to a new tempfile, returning the closed tempfile.
    def copy_to_temp_file(file, temp_base_name)
      Tempfile.new(temp_base_name, AttachmentMagic.tempfile_path).tap do |tmp|
        tmp.close
        FileUtils.cp file, tmp.path
      end
    end

    # Writes the given data to a new tempfile, returning the closed tempfile.
    def write_to_temp_file(data, temp_base_name)
      Tempfile.new(temp_base_name, AttachmentMagic.tempfile_path).tap do |tmp|
        tmp.binmode
        tmp.write data
        tmp.close
      end
    end
  end

  module InstanceMethods
    def self.included(base)
      base.define_callbacks *[:after_attachment_saved] if base.respond_to?(:define_callbacks)
    end

    # Sets the content type.
    def content_type=(new_type)
      write_attribute :content_type, new_type.to_s.strip
    end
    
    # Detects the mime-type if content_type is 'application/octet-stream'
    def detect_mimetype(file_data)
      if file_data.content_type.strip == "application/octet-stream"
        return File.mime_type?(file_data.original_filename)
      else
        return file_data.content_type
      end
    end

    # Sanitizes a filename.
    def filename=(new_name)
      write_attribute :filename, sanitize_filename(new_name)
    end

    # Returns true if the attachment data will be written to the storage system on the next save
    def save_attachment?
      File.file?(temp_path.class == String ? temp_path : temp_path.to_filename)
    end

    # nil placeholder in case this field is used in a form.
    def uploaded_data() nil; end

    # This method handles the uploaded file object.  If you set the field name to uploaded_data, you don't need
    # any special code in your controller.
    #
    #   <% form_for :attachment, :html => { :multipart => true } do |f| -%>
    #     <p><%= f.file_field :uploaded_data %></p>
    #     <p><%= submit_tag :Save %>
    #   <% end -%>
    #
    #   @attachment = Attachment.create! params[:attachment]
    #
    # TODO: Allow it to work with Merb tempfiles too.
    def uploaded_data=(file_data)
      if file_data.respond_to?(:content_type)
        return nil if file_data.size == 0
        self.content_type = detect_mimetype(file_data)
        self.filename     = file_data.original_filename if respond_to?(:filename)
      else
        return nil if file_data.blank? || file_data['size'] == 0
        self.content_type = file_data['content_type']
        self.filename =  file_data['filename']
        file_data = file_data['tempfile']
      end
      if file_data.is_a?(StringIO)
        file_data.rewind
        set_temp_data file_data.read
      else
        self.temp_paths.unshift file_data.tempfile.path
      end
    end

    # Gets the latest temp path from the collection of temp paths.  While working with an attachment,
    # multiple Tempfile objects may be created for various processing purposes (resizing, for example).
    # An array of all the tempfile objects is stored so that the Tempfile instance is held on to until
    # it's not needed anymore.  The collection is cleared after saving the attachment.
    def temp_path
      p = temp_paths.first
      p.respond_to?(:path) ? p.path : p.to_s
    end

    # Gets an array of the currently used temp paths.  Defaults to a copy of #full_filename.
    def temp_paths
      @temp_paths ||= (new_record? || !respond_to?(:full_filename) || !File.exist?(full_filename) ?
        [] : [copy_to_temp_file(full_filename)])
    end

    # Gets the data from the latest temp file.  This will read the file into memory.
    def temp_data
      save_attachment? ? File.read(temp_path) : nil
    end

    # Writes the given data to a Tempfile and adds it to the collection of temp files.
    def set_temp_data(data)
      temp_paths.unshift write_to_temp_file data unless data.nil?
    end

    # Copies the given file to a randomly named Tempfile.
    def copy_to_temp_file(file)
      self.class.copy_to_temp_file file, random_tempfile_filename
    end

    # Writes the given file to a randomly named Tempfile.
    def write_to_temp_file(data)
      self.class.write_to_temp_file data, random_tempfile_filename
    end

    # Stub for creating a temp file from the attachment data.  This should be defined in the backend module.
    def create_temp_file() end

    protected
      # Generates a unique filename for a Tempfile.
      def random_tempfile_filename
        "#{rand Time.now.to_i}#{filename || 'attachment'}"
      end

      def sanitize_filename(filename)
        return unless filename
        filename.strip.tap do |name|
          # NOTE: File.basename doesn't work right with Windows paths on Unix
          # get only the filename, not the whole path
          name.gsub! /^.*(\\|\/)/, ''

          # Finally, replace all non alphanumeric, underscore or periods with underscore
          name.gsub! /[^A-Za-z0-9\.\-]/, '_'
        end
      end

      # before_validation callback.
      def set_size_from_temp_path
        self.size = File.size(temp_path) if save_attachment?
      end

      # validates the size and content_type attributes according to the current model's options
      def attachment_attributes_valid?
        [:size, :content_type].each do |attr_name|
          enum = attachment_options[attr_name]
          errors.add attr_name, I18n.translate("activerecord.errors.messages.inclusion", attr_name => enum) unless enum.nil? || enum.include?(send(attr_name))
        end
      end

      # Stub for a #process_attachment method in a processor
      def process_attachment
        @saved_attachment = save_attachment?
      end

      # Cleans up after processing.  Thumbnails are created, the attachment is stored to the backend, and the temp_paths are cleared.
      def after_process_attachment
        if @saved_attachment
          save_to_storage
          @temp_paths.clear
          @saved_attachment = nil
        end
      end

      def callback_with_args(method, arg = self)
        send(method, arg) if respond_to?(method)
      end

  end
  
end

ActiveRecord::Base.send(:extend, AttachmentMagic::ActMethods)
