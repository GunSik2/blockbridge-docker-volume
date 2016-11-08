# Copyright (c) 2015-2016, Blockbridge Networks LLC.  All rights reserved.
# Use of this source code is governed by a BSD-style license, found
# in the LICENSE file.

require 'blockbridge/api'

module Helpers
  module BlockbridgeApi
    def self.client
      @@client ||= {}
    end

    def self.session
      @@session ||= {}
    end

    def session_token_valid?(otp)
      return unless BlockbridgeApi.session[vol_name]
      return unless BlockbridgeApi.session[vol_name][:otp] == otp
      true
    end

    def get_session_token(otp)
      return unless session_token_valid?(otp)
      BlockbridgeApi.session[vol_name][:token]
    end

    def set_session_token(otp, token)
      BlockbridgeApi.session[vol_name] = {
        otp:   otp,
        token: token,
      }
    end

    def bbapi_client_handle(user, user_token, otp)
      "#{access_token(user_token)}:#{user}:#{otp}"
    end

    def access_token(user_token)
      if user_token
        user_token
      else
        system_access_token
      end
    end

    def session_token_expires_in
      60
    end

    def client_params(user, user_token, otp)
      Hash.new.tap do |p|
        p[:user] = user || ''
        if user && (user_token.nil? || user_token == system_access_token)
          p[:default_headers] = {
            'X-Blockbridge-SU' => user,
          }
        end
        if otp
          p[:default_headers] ||= {}
          p[:default_headers]['X-Blockbridge-OTP'] = otp
        end
        p[:url] = api_url(access_token(user_token))
      end
    end

    def bbapi(user = nil, user_token = nil, otp = nil)
      BlockbridgeApi.client[bbapi_client_handle(user, user_token, otp)] ||=
        begin
          Blockbridge::Api::Client.defaults[:ssl_verify_peer] = false
          api = Blockbridge::Api::Client.new_oauth(access_token(user_token),
                                                   client_params(user, user_token, otp))
          if otp
            authz = api.oauth2_token.create(expires_in: session_token_expires_in)
            set_session_token(otp, authz.access_token)
          end
          api
        end
    end

    def bb_lookup_vol(vol_name, user, user_token = nil)
      vols = bbapi(user, user_token).vdisk.list(label: vol_name)
      raise Blockbridge::NotFound, "No volume #{vol_name} found" if vols.empty?
      vols.first
    end

    def bb_remove_vol(vol_name, user, user_token = nil)
      vol = bb_lookup_vol(vol_name, user, user_token)
      bbapi(user, user_token).objects.remove_by_xref("#{volume_ref_prefix}#{vol_name}", scope: "vdisk,xmd")
      if bbapi(user, user_token).vdisk.list(vss_id: vol.vss_id).empty?
        bbapi(user, user_token).vss.remove(vol.vss_id)
      end
    rescue Excon::Errors::NotFound, Excon::Errors::Gone, Blockbridge::NotFound, Blockbridge::Api::NotFoundError
    end

    def bb_lookup_s3(vol, user_token, params)
      s3_params = {}
      s3_params[:label] = params[:s3] if params[:s3]
      s3s = bbapi(vol[:user], user_token).obj_store.list(s3_params)
      raise Blockbridge::NotFound, "No S3 object store found for #{vol[:user]}" if s3s.empty?
      if s3s.length > 1
        raise Blockbridge::Conflict, "More than one S3 object store found; please specify one"
      end
      s3s.first
    end

    def bb_backup_vol(vol, user_token, params)
      vdisk = bb_lookup_vol(vol[:name], vol[:user], user_token)
      s3obj = bb_lookup_s3(vol, user_token, params)
      params = { obj_store_id: s3obj.id, snapshot_id: nil, async: true }
      bbapi(vol[:user], user_token).vdisk.backup(vdisk.id, params)
    end

    def bb_lookup_user(user)
      raise Blockbridge::NotFound if bbapi.user_profile.list(login: user).length == 0
    end

    def bb_lookup_vol_info(vol)
      bb_lookup_user(vol[:user])
      info = bbapi.xmd.info("docker-volume-#{vol[:name]}")
      info[:data].merge(info[:data][:volume])
    rescue Excon::Errors::NotFound, Excon::Errors::Gone, Blockbridge::NotFound, Blockbridge::Api::NotFoundError
    end

    def bb_host_attached(ref, user, user_token = nil)
      bbapi(user, user_token).xmd.info(ref)
    rescue Excon::Errors::NotFound, Excon::Errors::Gone, Blockbridge::NotFound, Blockbridge::Api::NotFoundError
    end

    def bb_get_attached(vol_name, user, user_token = nil)
      vol = bb_lookup_vol(vol_name, user, user_token)
      attached = vol.xmd_refs.select { |x| x.start_with? "host-attach" }
      return unless attached.length > 0
      attached.map! { |ref|
        bb_host_attached(ref, user, user_token)
      }.compact!
      return unless attached.length > 0
      attached
    rescue Excon::Errors::NotFound, Excon::Errors::Gone, Blockbridge::NotFound, Blockbridge::Api::NotFoundError
    end
  end
end
