Given /^there is a deployment named "([^"]*)" belonging to "([^"]*)" owned by "([^"]*)"$/ do |deployment_name, deployable_name, owner_name|
  user = Factory(:user, :login => owner_name)
  deployable = Deployable.create!(:name => deployable_name, :owner => user)
  deployable.deployments.create!({:name => deployment_name, :pool => Pool.first, :owner => user})
end
