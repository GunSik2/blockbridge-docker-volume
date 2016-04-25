# Copyright (c) 2015-2016, Blockbridge Networks LLC.  All rights reserved.
# Use of this source code is governed by a BSD-style license, found
# in the LICENSE file.

require 'blockbridge/api'

module Helpers
  module BlockbridgeApi
    def self.bbapi_client
      @@bbapi_client ||= {}
    end

    def bbapi_client_handle(user, user_token)
      "#{access_token(user_token)}:#{user}"
    end

    def access_token(user_token)
      if user_token
        user_token
      else
        system_access_token
      end
    end

    def url
      if api_host
        "https://#{api_host}/api"
      elsif api_url
        api_url
      end
    end

    def client_params(user, user_token)
      Hash.new.tap do |p|
        p[:user] = user || ''
        if user && user_token.nil?
          p[:default_headers] = {
            'X-Blockbridge-SU' => user,
          }
        end
        p[:url] = url
      end
    end

    def bbapi(user = nil, user_token = nil)
      BlockbridgeApi.bbapi_client[bbapi_client_handle(user, user_token)] ||=
        begin
          Blockbridge::Api::Client.defaults[:ssl_verify_peer] = false
          Blockbridge::Api::Client.new_oauth(access_token(user_token),
                                             client_params(user, user_token))
        end
    end

    def bb_lookup(vol_name, user, user_token = nil)
      vols = bbapi(user, user_token).vdisk.list(label: vol_name)
      raise Blockbridge::NotFound if vols.empty?
      vols.first
    end

    def bb_remove(vol_name, user, user_token = nil)
      disk = bb_lookup(vol_name, user, user_token)
      bbapi(user, user_token).objects.remove_by_xref("#{volume_ref_prefix}#{vol_name}", scope: "vdisk,xmd")
      if bbapi(user, user_token).vdisk.list(vss_id: disk.vss_id).empty?
        bbapi(user, user_token).vss.remove(disk.vss_id)
      end
    rescue Blockbridge::NotFound
    end

    def bb_host_attached(ref, user, user_token = nil)
      bbapi(user, user_token).xmd.info(ref)
    rescue Excon::Errors::NotFound
    end

    def bb_is_attached(vol_name, user, user_token = nil)
      disk = bb_lookup(vol_name, user, user_token)
      attached = disk.xmd_refs.select { |x| x.start_with? "host-attach" }
      return unless attached.length > 0
      attached.map! { |ref|
        bb_host_attached(ref, user, user_token)
      }.compact!
      return true if attached.length > 0
    rescue Blockbridge::NotFound, Excon::Errors::NotFound
    end
  end
end
