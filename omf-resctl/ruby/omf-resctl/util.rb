def findBinary(bin, path = %w(/usr/bin/ /usr/sbin/ /bin/ /sbin/))
	names = path.map do |path| path + bin end
	names.find do |bin| File.exist?(bin) end
end
