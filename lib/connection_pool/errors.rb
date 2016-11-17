class ConnectionPool::Error < RuntimeError
end

class ConnectionPool::CheckedInUnCheckedOutConnectionError < ConnectionPool::Error
end

