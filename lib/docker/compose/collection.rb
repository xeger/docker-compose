module Docker::Compose
  class Collection < Array
    # @example find containers that are up
    #   who_is_up = coll.where { |c| c.up? }
    # @example count space taken by all containers
    #   coll.map { |c| c.size }.inject(0) { |a, x| a + x }
    def where
      hits = Collection.new
      self.each { |c| hits << c if yield(c) }
      hits
    end
  end
end