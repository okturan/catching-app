# Signing in without the form: a session row and the signed cookie a browser
# would carry for it.
module SessionTestHelper
  def sign_in(user)
    session = user.sessions.create!
    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[:session_id] = session.id
      cookies["session_id"] = cookie_jar[:session_id]
    end
  end
end
