class Search < ActiveRecord::Base

  attr_accessor :pagination

  class << self
    def columns
      @columns ||= [];
    end

    def column(name, sql_type = nil, default = nil, null = true)
      columns << ActiveRecord::ConnectionAdapters::Column.new(name.to_s, default,
        sql_type.to_s, null)
    end

    def column_defaults
      columns.map(&:name).inject({}) do | hash, name | hash[name] = nil; hash end
    end

    def columns_hash
      columns.inject({}) do | hash, column | hash[column.name] = column; hash end
    end
  end

  def pagination
    @pagination ||= {}
    @pagination.merge! per_page: per_page if respond_to? :per_page
    @pagination
  end

  delegate :results, :to => :search
  delegate :total, :to => :search

  def result_ids
    search.hits.map(&:primary_key)
  end

  protected

    def search
      Sunspot.search klass do | search |
        search.keywords keywords if search_columns.delete("keywords")
        search_columns.each do | column |
          value = normalize(column)
          if column_for_attribute(column).type == :text && self.class.serialized_attributes[column] != Array
            if fuzzy?(value)
              search.adjust_solr_params do |params|
                params[:q] = value.split(/ /).map{ |value| "#{column}_text:#{value}"}.join(' ')
              end
            else
              search.keywords value, :fields => column
            end
          else
            case column
            when /_lt$/
              search.with(column[0..-4]).less_than(value)
            when /_gt$/
              search.with(column[0..-4]).greater_than(value)
            else
              search.with column, value
            end
          end
        end
        additional_search
        search.order_by *order_by.split(' ') if respond_to?(:order_by) && order_by.present?
        search.paginate pagination if pagination.try(:any?)
      end
    end

    def additional_search
    end

    def save(validate = true)
      validate ? valid? : true
    end

    def search_columns
      @search_columns ||= (self.class.column_names - %w[per_page order_by]).select{ |column| normalize(column).present? }
    end

    def normalize(column)
      if respond_to?("normalize_#{column}")
        send "normalize_#{column}"
      elsif self.class.serialized_attributes[column] == Array
        [*self.send("#{column}_before_type_cast")].select(&:present?)
      elsif column_for_attribute(column).type == :integer
        self[column].try(:zero?) ? nil : self[column]
      elsif column_for_attribute(column).type == :text && column =~ /term$/
        normalize_term_column(self[column])
      else
        self[column]
      end
    end

    def normalize_term_column(text)
      text.gsub(/[^[:alnum:]~]+/, ' ').strip if text
    end

    def fuzzy?(text)
      text =~ /~/
    end

    def klass
      self.class.model_name.classify.gsub(/Search$/, '').constantize
    end

end
