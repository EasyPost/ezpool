class ConnectionPool::Error < RuntimeError
end

class ConnectionPool::CheckedInUnCheckedOutConnectionError < ConnectionPool::Error
end

class ConnectionPool::ConnectCallableNeverConfigured < ConnectionPool::Error
end
