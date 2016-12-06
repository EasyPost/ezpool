class EzPool::Error < RuntimeError
end

class EzPool::CheckedInUnCheckedOutConnectionError < EzPool::Error
end

class EzPool::ConnectCallableNeverConfigured < EzPool::Error
end
