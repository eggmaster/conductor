Factory.define :deployable do |a|
  a.sequence(:name) { |n| "deployable#{n}" }
  a.assemblies { |t| [t.association(:assembly)] }
  a.association :owner, :factory => :user
end
