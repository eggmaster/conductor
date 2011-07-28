class InstanceObserver < ActiveRecord::Observer

  ACTIVE_STATES = [ Instance::STATE_PENDING, Instance::STATE_RUNNING, Instance::STATE_SHUTTING_DOWN, Instance::STATE_STOPPED ]
  RUNNING_STATES = [ Instance::STATE_PENDING, Instance::STATE_RUNNING, Instance::STATE_SHUTTING_DOWN ]

  def before_save(an_instance)
    if an_instance.changed?
      change = an_instance.changes['state']
      if change
        update_state_timestamps(change[1], an_instance)
        update_accumulative_state_time(change[0], an_instance)
        update_quota(change[0], change[1], an_instance)
      end
    end
  end

  def update_state_timestamps(state_to, an_instance)
    case state_to
      when Instance::STATE_PENDING then an_instance.time_last_pending = Time.now
      when Instance::STATE_RUNNING then an_instance.time_last_running = Time.now
      when Instance::STATE_SHUTTING_DOWN then an_instance.time_last_shutting_down = Time.now
      when Instance::STATE_STOPPED then an_instance.time_last_stopped = Time.now
    end
  end

  def update_accumulative_state_time(state_from, an_instance)
    case state_from
      when Instance::STATE_PENDING then an_instance.acc_pending_time += Time.now - an_instance.time_last_pending
      when Instance::STATE_RUNNING then an_instance.acc_running_time += Time.now - an_instance.time_last_running
      when Instance::STATE_SHUTTING_DOWN then an_instance.acc_shutting_down_time += Time.now - an_instance.time_last_shutting_down
      when Instance::STATE_STOPPED then an_instance.acc_stopped_time += Time.now - an_instance.time_last_stopped
    end
  end

  def update_quota(state_from, state_to, an_instance)
    pool = an_instance.pool
    pool_family = pool.pool_family
    user = an_instance.owner
    provider_account = an_instance.provider_account

    [provider_account, pool_family, pool, user].each do |parent|
      if parent
        # Since pool and pool_family are related, updating one can cause the other to become stale
        parent.reload if parent.class == Pool
        quota = parent.quota
        if quota
          if !RUNNING_STATES.include?(state_from) && RUNNING_STATES.include?(state_to)
            quota.running_instances += 1
          elsif RUNNING_STATES.include?(state_from) && !RUNNING_STATES.include?(state_to)
            quota.running_instances -= 1
          end

          if !ACTIVE_STATES.include?(state_from) && ACTIVE_STATES.include?(state_to)
            quota.total_instances += 1
          elsif ACTIVE_STATES.include?(state_from) && !ACTIVE_STATES.include?(state_to)
            quota.total_instances -= 1
          end
          quota.save!
        end
      end
    end
  end

  def after_create(instance)
    event = Event.new(:source => instance, :event_time => instance.created_at,
                      :summary => "created")
    event.save!
  end

  def after_update(instance)
    if instance.state_changed?
      event = Event.new(:source => instance, :event_time => DateTime.now,
                        :summary => "state changed to #{instance.state}")
      event.save!
    end
  end

  def after_save(instance)
    if instance.state_changed? and
       instance.state == Instance::STATE_STOPPED and
       instance.deployment and
       instance.deployment.scheduled_for_deletion and
       instance.deployment.destroyable?

      instance.deployment.destroy
    end
  end

end

InstanceObserver.instance
