module Scrapers
  class TitleParser
    # Parses raw titles from teatras.lt into clean title + author + based_on.
    #
    # Patterns supported:
    #   "Kazys Binkis. ATŽALYNAS" -> title: "Atžalynas", author: "Kazys Binkis"
    #   "Pagal David Foster Wallace esė. APMĄSTANT OMARĄ" -> title: "Apmąstant omarą", based_on: "Pagal David Foster Wallace esė"
    #   "METAMORFOZĖ. Pagal Franzo Kafkos kūrybą" -> title: "Metamorfozė", based_on: "Pagal Franzo Kafkos kūrybą"
    #   "RESPUBLIKA" -> title: "Respublika"
    #   "Naubertas Jasinskas. VELNIO NUOTAKA Premjera" -> title: "Velnio nuotaka", author: "Naubertas Jasinskas"
    Result = Struct.new(:title, :author, :based_on, keyword_init: true)

    def self.parse(raw)
      new(raw).parse
    end

    def initialize(raw)
      @raw = raw.to_s.strip.sub(/\s+Premjera\s*\z/, "")
    end

    def parse
      return Result.new(title: nil, author: nil, based_on: nil) if @raw.empty?

      # Pattern: "Pagal X. TITLE" -> based_on first.
      if @raw =~ /\A(Pagal\s+[^.]+?)\.\s+(.+)\z/i
        return Result.new(title: titleize_smart(Regexp.last_match(2)), author: nil, based_on: Regexp.last_match(1).strip)
      end

      # Pattern: "TITLE. Pagal X" -> title first, based_on second.
      if @raw =~ /\A(.+?)\.\s+(Pagal\s+.+)\z/i
        return Result.new(title: titleize_smart(Regexp.last_match(1)), author: nil, based_on: Regexp.last_match(2).strip)
      end

      # Pattern: "Author. TITLE" - split on first ". " if second part is mostly uppercase.
      if @raw.include?(". ")
        first, second = @raw.split(". ", 2)
        if mostly_uppercase?(second)
          return Result.new(title: titleize_smart(second), author: first.strip, based_on: nil)
        end
      end

      # Fallback: whole thing is the title (possibly all-caps).
      Result.new(title: titleize_smart(@raw), author: nil, based_on: nil)
    end

    private

    # True if 70%+ of letters in the string are uppercase.
    def mostly_uppercase?(str)
      # Parenthetical clarifiers do not affect the title's "shouting" character.
      stripped = str.gsub(/\([^)]*\)/, "")
      letters = stripped.scan(/\p{Alpha}/)
      return false if letters.empty?

      upper_count = letters.count { |letter| letter == letter.upcase && letter != letter.downcase }
      (upper_count.to_f / letters.size) >= 0.7
    end

    # Converts all-caps strings to sentence-case (first letter cap, rest lower).
    # Strings already in proper case are returned unchanged.
    def titleize_smart(str)
      return str if str.nil? || str.empty?
      return str unless mostly_uppercase?(str)

      result = str.downcase
      result = result.sub(/(\p{Alpha})/) { Regexp.last_match(1).upcase }
      result.gsub(/(\.\s+)(\p{Alpha})/) { Regexp.last_match(1) + Regexp.last_match(2).upcase }
    end
  end
end
