require 'logger'
require 'open-uri'
require 'hpricot'
require 'uri'
require 'base64'

module EmbedHtml
  class Embeder
    MAX_CONCURRENCY = 5
    
    attr_accessor :url
    attr_accessor :logger
    
    def initialize(url, logger=Logger.new($stdout))
      @logger = logger
      @url = url
    end
    
    def process
      @logger.info "downloading url: #{@url}"
      html = open(@url.to_s).read
      doc = Hpricot(html)
      
      hydra = Typhoeus::Hydra.new(:max_concurrency => MAX_CONCURRENCY)
      doc.search("//img").each do |img|                
        begin
          hydra.queue create_fetch_file_request(img, 'src')
        rescue StandardError => e
          @logger.error "failed download image: #{img['src']}"
        end
      end

      doc.search("//script").each do |script|                
        begin
          hydra.queue create_fetch_file_request(script, 'src')
        rescue StandardError => e
          @logger.error "failed download script: #{script['src']}"
        end
      end

      doc.search("//link").each do |link|
        begin
          hydra.queue create_fetch_file_request(link, 'href')
        rescue StandardError => e
          @logger.error "failed download linked resource: #{link['href']}"
        end
      end
      
      hydra.run

      @logger.info "done"            
      doc.to_html      
    end
    
    private
    def create_fetch_file_request(element, field)
      file_url = URI.join(@url, element.attributes[field])
      @logger.debug "queue download file: #{file_url}"

      request = Typhoeus::Request.new(file_url.to_s)
      request.on_complete do |response|
        data = response.body
        type = response.headers_hash["Content-Type"]
        if data && type
          data_b64 = Base64.encode64(data)
          element.attributes[field] = "data:#{type};base64,#{data_b64}"
        end  
      end
      return request
    end
    
  end
end