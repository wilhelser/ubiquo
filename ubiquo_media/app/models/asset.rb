require "fileutils"

# An asset is a resource with name, description and one associated
# file.
#
# This model has no associated file right away. The sublcasses AssetPublic and
# AssetProtected have the attribute :resource as a file_attachment and so they
# are the models to work with.
class Asset < ActiveRecord::Base
  BACKUP_EXTENSION = ".bak" # Extension to copy the backup
  belongs_to :asset_type

  has_many :asset_relations, :dependent => :destroy
  has_many :asset_areas, :dependent => :destroy
  has_many :asset_geometries, :dependent => :destroy

  validates :name, :asset_type_id, :type, :presence => true
  before_validation :set_asset_type, :on => :create
  after_update :uhook_after_update
  attr_accessor :duplicated_from
  after_create :save_backup_on_dup
  after_save :update_backup
  after_save :save_geometries

  attr_accessible :name, :description, :asset_type_id, :resource_file_name,
    :resource_file_size, :resource_content_type, :type, :is_protected,
    :keep_backup, :resource, :asset_type

  scope :type, lambda { |t|
    where("asset_type_id IN (?)", t.to_s.split(',').map(&:to_i))
  }

  scope :visibility, lambda { |visibility|
    where(:type => "asset_#{visibility}".classify)
  }

  scope :created_start, lambda { |created_start|
    where("created_at >= ?", parse_date(created_start))
  }

  scope :created_end, lambda { |created_end|
    where("created_at <= ?", parse_date(created_end, :time_offset => 1.day))
  }

  filtered_search_scopes :text => [:name, :description],
                         :enable => [:type, :visibility, :created_start, :created_end]

  # Generic find (ID, key or record)
  def self.gfind(something, options={})
    case something
    when Fixnum
      find_by_id(something, options)
    when String, Symbol
      find_by_name(something.to_s, options)
    when Asset
      something
    else
      nil
    end
  end

  # To mantain backwards compatibility with old filters
  def self.filtered_search(filters = {}, options = {})
    new_filters = {}
    filters.each do |key, value|
      if key == :type
        new_filters["filter_type"] = value
      elsif key == :text
        new_filters["filter_text"] = value
      elsif key == :visibility
        new_filters["filter_visibility"] = value
      elsif key == :created_start
        new_filters["filter_created_start"] = value
      elsif key == :created_end
        new_filters["filter_created_end"] = value
      else
        new_filters[key] = value
      end
    end

    super new_filters, options
  end

  def self.visibilize(visibility)
    "asset_#{visibility}".classify.constantize
  end

  # Correct parameters to the resize_and_crop processor.
  # If the processor is other, the extra params will be ignored
  #
  # @return <lambda> It will be processed by paperclip to get the styles
  def self.correct_styles(styles_list = {})
    global_options = Ubiquo::Settings.context(:ubiquo_media).get(:media_styles_options)

    _styles = styles_list.map do |style, value|
      extra_options = global_options.is_a?(Proc) ? global_options.call(style, value) : global_options
      [style, {:geometry => value, :style_name => style}.merge(extra_options)]
    end.to_hash

    # Only process images
    # link: http://stackoverflow.com/questions/5289674/paperclip-process-images-only
    lambda do |a|
      result = {}
      if a.nil? || a.content_type.nil? || a.content_type.include?('image')
        result = _styles
      end

      result
    end
  end

  def is_resizeable?
    self.asset_type && self.asset_type.key == "image" && self.resource
  end

  def backup_path
    self.resource.path + BACKUP_EXTENSION
  end

  # Backups the original file if backup does not exist
  def backup
    self.keep_backup && !File.exists?( backup_path ) && FileUtils.cp( self.resource.path, backup_path )
  end

  # Restores the backuped file. Returns true when restored successfully
  def restore!
    if restorable?
      FileUtils.mv backup_path, self.resource.path
      self.asset_areas.destroy_all
      self.resource.reprocess!
      # The asset must be saved to refresh update_at field for a correct caching of the asset
      self.save!
      true
    end
  end

  def restorable?
    File.exists? backup_path
  end

  # dup the asset (not the related models) and the resource
  # NOTE: We want the dup method, not the clone. From the Rails 3 doc:
  #
  # ActiveRecord::Base#dup and ActiveRecord::Base#clone semantics have changed
  # to closer match normal Ruby dup and clone semantics.
  #
  # Calling ActiveRecord::Base#clone will result in a shallow copy of the
  # record, including copying the frozen state. No callbacks will be called.
  #
  # Calling ActiveRecord::Base#dup will duplicate the record, including calling
  # after initialize hooks. Frozen state will not be copied, and all
  # associations will be cleared. A duped record will return true for
  # new_record?, have a nil id field, and is saveable.
  def dup
    obj                 = super
    obj.duplicated_from = self
    obj.resource        = self.resource_file
    uhook_duplicated_object(obj)

    obj
  end

  def dup?
    self.duplicated_from ? true : false
  end

  def geometry(style = :original)
    asset_geometry = self.asset_geometries.find_by_style(style.to_s)

    unless asset_geometry
      asset_geometry = calculate_geometry(style)
      if asset_geometry
        asset_geometry.asset_id = self.id
        asset_geometry.save
      end
    end

    asset_geometry.generate if asset_geometry
  end

  def keep_backup
    # keep backups only in filesystem
    return false unless self.resource.options[:storage] == :filesystem

    self[:keep_backup]
  end

  def resource_file(style = :original)
    if self.resource
      queued = (self.resource.queued_for_write[style].send(:destination) rescue false)
      if !queued
        resource = style == :original ? self.resource : self.resource.styles[style]
        stored = Paperclip.io_adapters.for(resource)
      end
      queued || stored
    end
  end

  private

  def set_asset_type
    if self.resource_file_name && self.resource.errors.blank?
      # mime_types hash is here momentarily but maybe its must be in ubiquo config
      mime_types = Ubiquo::Settings.context(:ubiquo_media).get(:mime_types)
      content_type = self.resource_content_type.split('/') rescue []
      mime_types.each do |type_relations|
        type_relations.last.each do |mime|
          if content_type.include?(mime)
            self.asset_type = AssetType.find_by_key(type_relations.first.to_s)
          end
        end
      end
      self.asset_type = AssetType.find_by_key("other") unless self.asset_type
    end
  end

  # Keeps the backup file when an asset has been duplicated
  def save_backup_on_dup
    if self.duplicated_from && self.duplicated_from.restorable? && self.keep_backup
      FileUtils.mkdir_p( File.dirname( self.backup_path ))
      FileUtils.cp( self.duplicated_from.backup_path, self.backup_path )
    end
  end

  def update_backup
    unless self.keep_backup
      # Delete backup
      File.unlink( self.backup_path ) if File.exists?( self.backup_path )
    end
  end

  def generate_geometries
    self.asset_geometries.destroy_all

    unless self.dup?
      @asset_geometries_to_save = []

      if self.resource && self.resource_content_type.include?('image')
        self.resource.styles.map { |s| s.first }.each do |style|
          @asset_geometries_to_save << calculate_geometry(style)
        end
        @asset_geometries_to_save << calculate_geometry
      end
    end
  end

  def save_geometries
    unless self.dup?
      @asset_geometries_to_save ||= []

      self.asset_geometries.destroy_all unless @asset_geometries_to_save.empty?
      @asset_geometries_to_save.each do |asset_geometry|
        asset_geometry.asset_id = self.id
        asset_geometry.save
      end
    end
  end

  def calculate_geometry(style = :original)
    AssetGeometry.from_file(self.resource_file(style), style)
  end

end
