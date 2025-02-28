class Services::Edit::Approve < Services::Edit::Moderate

  def initialize(edit)
    super
    @apply = Services::Edit::Apply.new(@edit)
  end

  def state
    :approved
  end

  def callable?
    @apply.callable? # Delegates to another service.
  end

  def perform
    ActiveRecord::Base.transaction do
      @edit.approved
      @edit.send state
      @apply.call
    end
  end
end
