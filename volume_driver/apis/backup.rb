# Copyright (c) 2015-2016, Blockbridge Networks LLC.  All rights reserved.
# Use of this source code is governed by a BSD-style license, found
# in the LICENSE file.

class API::Backup < Grape::API
  prefix 'backup'

  desc 'list backups'
  params do
    optional :profile, type: String, desc: 'list backups from S3 object store defined in profile'
    optional :s3,      type: String, desc: 'list backups from S3 object store'
  end
  get do
    body(backup_ls)
  end

  resource :info do
    desc 'S3 Object store info'
    get do
      body(backup_info)
    end
  end

  route_param :s3 do
    route_param :backup do
      desc 'Inspect backup'
      get do
        body(backup_inspect)
      end

      desc 'Delete backup'
      delete do
        status 204
        synchronize do
          backup_rm
        end
      end
    end
  end

  route_param :backup do
    desc 'Inspect backup'
    get do
      body(backup_inspect)
    end

    desc 'Delete backup'
    delete do
      status 204
      synchronize do
        backup_rm
      end
    end
  end
end
