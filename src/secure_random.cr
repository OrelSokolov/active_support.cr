# SecureRandom — Rails-compatible random string generation on top of
# Crystal's Random::Secure.
module SecureRandom
  ALPHANUMERIC_CHARS = ("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a

  def self.alphanumeric(length : Int = 32) : String
    String.build do |io|
      length.times { io << ALPHANUMERIC_CHARS.sample(Random::Secure) }
    end
  end
end
