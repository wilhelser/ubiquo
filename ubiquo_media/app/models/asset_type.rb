class AssetType < ActiveRecord::Base
  has_many :assets

  attr_accessible :name, :key

  # Generic find (ID, key or record)
  def self.gfind(something, options={})
    case something
    when Fixnum
      find_by_id(something, options)
    when String, Symbol
      find_by_key(something.to_s, options)
    when AssetType
      something
    else
      nil
    end
  end

  # Returns the AssetTypes that fit this types.
  # Expects an array of keys [:image, :other] or the symbol :ALL
  def self.get_by_keys( types )
    types = [types].flatten.compact.map(&:to_sym)
    if(types.include?(:ALL) || types.blank?)
      AssetType.find(:all)
    else
      types.map{|o|AssetType.gfind(o)}.compact
    end
  end

end
