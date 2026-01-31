using AgroSolutions.Identity.Domain.Notifications;

namespace AgroSolutions.Identity.Domain.Interfaces;

public interface INotifier
{
    bool HasNotification();
    List<Notification> GetNotifications();
    void Handle(Notification notification);
}
