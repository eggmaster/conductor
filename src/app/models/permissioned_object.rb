#
#   Copyright 2011 Red Hat, Inc.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

module PermissionedObject

  def has_privilege(user, action, target_type=nil)
    return false if user.nil? or action.nil?
    target_type = self.class.default_privilege_target_type if target_type.nil?
    perm_ancestors.each do |obj|
      return true if obj and obj.permissions.find(:first,
                                          :include => [:role => :privileges],
                                          :conditions =>
                                          ["permissions.user_id=:user and
                                            privileges.target_type=:target_type and
                                            privileges.action=:action",
                                           { :user => user.id,
                                             :target_type => target_type.name,
                                             :action => action}])
    end
    return false
  end

  # Returns the list of objects to check for permissions on -- by default
  # this object plus the Base permission object
  # At the moment, the retuned list is not necessarily ordered
  # FIXME: remove self once has_privilege stops using this method
  def perm_ancestors
    [self, BasePermissionObject.general_permission_scope]
  end
  # Returns the list of objects to generate derived permissions for
  # -- by default just this object
  def derived_subtree(role = nil)
    [self]
  end
  # on obj creation, set inherited permissions for new object
  def update_derived_permissions_for_ancestors
    # for create hook this should normally be empty
    old_derived_permissions = Hash[derived_permissions.map{|p| [p.permission.id,p]}]
    perm_ancestors.each do |perm_obj|
      perm_obj.permissions.each do |permission|
        if permission.role.privilege_target_match(self.class.default_privilege_target_type)
          unless old_derived_permissions.delete(permission.id)
            derived_permissions.create(:user_id => permission.user_id,
                                       :role_id => permission.role_id,
                                       :permission => permission)
          end
        end
      end
    end
    # anything remaining in old_derived_permissions should be removed,
    # as would be expected if this hook is triggered by removing a
    # catalog entry for a deployable
    old_derived_permissions.each do |id, derived_perm|
      derived_perm.destroy
    end
    #reload
  end
  # assign owner role so that the creating user has permissions on the object
  # Any roles defined on default_privilege_target_type with assign_to_owner==true
  # will be assigned to the passed-in user on this object
  def assign_owner_roles(user)
    roles = Role.find(:all, :conditions => ["assign_to_owner =:assign and scope=:scope",
                                            { :assign => true,
                                              :scope => self.class.default_privilege_target_type.name}])
    roles.each do |role|
      Permission.create!(:role => role, :user => user, :permission_object => self)
    end
    self.reload
  end

  # Any methods here will be able to use the context of the
  # ActiveRecord model the module is included in.
  def self.included(base)
    base.class_eval do
      after_create :update_derived_permissions_for_ancestors

      # Returns the list of privilege target types that are relevant for
      # permission checking purposes. This is used in setting derived
      # permissions -- there's no need to create denormalized permissions
      # for a role which only grants Provider privileges on a Pool
      # object. By default, this is just the current object's type
      def self.active_privilege_target_types
        [self.default_privilege_target_type] + self.additional_privilege_target_types
      end
      def self.additional_privilege_target_types
        []
      end
      def self.default_privilege_target_type
        self
      end
      def self.list_for_user_include
        [:permissions]
      end
      def self.list_for_user_conditions
        "permissions.user_id=:user and
         permissions.role_id in (:role_ids)"
      end
      def self.list_for_user(user, action, target_type=self.default_privilege_target_type)
        return where("1=0") if user.nil? or action.nil? or target_type.nil?
        if BasePermissionObject.general_permission_scope.has_privilege(user, action, target_type)
          scoped
        else
          role_ids = Role.includes(:privileges).where("privileges.target_type" => target_type, "privileges.action" => action).collect {|r| r.id}
          include_clause = self.list_for_user_include
          conditions_hash = {:user => user.id, :target_type => target_type.name, :action => action, :role_ids => role_ids}
          conditions_str = self.list_for_user_conditions
          includes(include_clause).where(conditions_str, conditions_hash)
        end
      end
    end
  end

end
