require 'test_helper'

class GatekeeperPublishTest < ActionController::TestCase

  tests DataFilesController

  fixtures :all

  include AuthenticatedTestHelper

  def setup
    login_as(:datafile_owner)
    @object=data_files(:picture)
  end


  test 'should not allow to decide publishing for non-gatekeeper' do
    login_as(:quentin)
    df = Factory(:data_file,:projects => people(:quentin_person).projects)
    get :approve_or_reject_publish, :id=>df.id
    assert_redirected_to :root
    assert_not_nil flash[:error]

    post :gatekeeper_decide, :id => df.id, :gatekeeper_decision => 1
    assert_redirected_to :root
    assert_not_nil flash[:error]
  end

  test "gracefully handle approve_or_reject for deleted items" do
    gatekeeper = Factory(:gatekeeper)
    df = Factory(:data_file,:projects => gatekeeper.projects)
    login_as(df.contributor)
    put :update, :id => df.id, :sharing => {:sharing_scope => Policy::EVERYONE, "access_type#{Policy::EVERYONE}" => Policy::VISIBLE}

    id = df.id
    disable_authorization_checks do
      df.destroy
      assert_nil(DataFile.find_by_id(df.id))
    end

    logout
    login_as(gatekeeper.user)
    get :approve_or_reject_publish, :id=>0
    assert_redirected_to :root
    assert_not_nil flash[:error]
    assert_equal "This Data file no longer exists, and may have been deleted since the request to publish was made.",flash[:error]
  end

  test 'gatekeeper should be able to decide publishing' do
    gatekeeper = Factory(:gatekeeper)
    df = Factory(:data_file,:projects => gatekeeper.projects)
    login_as(df.contributor)
    put :update, :id => df.id, :sharing => {:sharing_scope => Policy::EVERYONE, "access_type#{Policy::EVERYONE}" => Policy::VISIBLE}

    logout

    login_as(gatekeeper.user)
    get :approve_or_reject_publish, :id=>df.id
    assert_response :success
    assert_nil flash[:error]

    post :gatekeeper_decide, :id => df.id, :gatekeeper_decision => 0
    assert_redirected_to data_file_path(df)
    assert_nil flash[:error]
    df.reload
    assert_not_equal Policy::EVERYONE, df.policy.sharing_scope

    post :gatekeeper_decide, :id => df.id, :gatekeeper_decision => 1
    assert_redirected_to data_file_path(df)
    assert_nil flash[:error]
    df.reload
    assert_equal Policy::EVERYONE, df.policy.sharing_scope
    assert_equal Policy::ACCESSIBLE, df.policy.access_type
  end

  test 'should not allow to decide publishing for gatekeeper from other projects' do
    gatekeeper = Factory(:gatekeeper)
    df = Factory(:data_file)
    login_as(df.contributor)
    put :update, :id => df.id, :sharing => {:sharing_scope => Policy::EVERYONE, "access_type#{Policy::EVERYONE}" => Policy::VISIBLE}
    logout

    assert (df.projects&gatekeeper.projects).empty?
    login_as(gatekeeper.user)
    get :approve_or_reject_publish, :id=>df.id
    assert_redirected_to :root
    assert_not_nil flash[:error]

    post :gatekeeper_decide, :id => df.id, :gatekeeper_decision => 1
    assert_redirected_to :root
    assert_not_nil flash[:error]
  end

  test 'do not allow to decide publishing if the asset is not in waiting_for_approval state' do
    gatekeeper = Factory(:gatekeeper)
    df = Factory(:data_file, :projects => gatekeeper.projects)

    login_as(gatekeeper.user)
    post :gatekeeper_decide, :id => df.id, :gatekeeper_decision => 1

    assert_redirected_to :root
    assert_not_nil flash[:error]
  end

  test 'allow to decide publishing if the asset is in waiting_for_approval state' do
    gatekeeper = Factory(:gatekeeper)
    df = Factory(:data_file, :projects => gatekeeper.projects)

    login_as(df.contributor)
    put :update, :id => df.id, :sharing => {:sharing_scope => Policy::EVERYONE, "access_type#{Policy::EVERYONE}" => Policy::VISIBLE}

    logout

    login_as(gatekeeper.user)
    post :gatekeeper_decide, :id => df.id, :gatekeeper_decision => 1

    assert_nil flash[:error]
  end
end